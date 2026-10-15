// ─────────────────────────────────────────────────────────────────────────────
// Push notifications (FCM HTTP v1).
//
// Both apps store an fcmToken (Driver.fcmToken, User.fcmToken) and there was no
// code anywhere that ever sent one — so every screen polls instead: the driver
// feed every 4 s, the rider's ride status every 3 s. That is the structural
// reason dispatch has to be a shared pull-pool rather than Rapido's "instantly
// notifies nearby captains" offer.
//
// Credentials come from either source, env winning:
//   1. env — FCM_PROJECT_ID, FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY
//   2. Settings.firebase in Mongo, editable at /settings/firebase in the admin
//
// Source 2 exists so going live does not require SSH + an .env edit + a PM2
// restart: paste the three service-account fields into the dashboard and the
// next push picks them up within CREDS_CACHE_TTL_MS.
//
// With neither set every call is a silent no-op, so dev and CI behave exactly
// as before.
// ─────────────────────────────────────────────────────────────────────────────
import crypto from 'crypto'
import { connectDB } from './mongodb'
import Settings from '@/models/Settings'

type PushMessage = {
  title: string
  body: string
  /** Delivered to the app as a data payload — keep values as strings. */
  data?: Record<string, string>
  /** Android channel; the driver app uses a high-priority ride channel. */
  channelId?: string
}

type Creds = { projectId: string; clientEmail: string; privateKey: string }

// Env vars carry "\n" escapes rather than real newlines; so does a private key
// pasted into a browser textarea, so both sources need the same normalisation.
function normaliseKey(k: string): string {
  return (k || '').replace(/\\n/g, '\n').trim()
}

function envCreds(): Creds | null {
  const projectId = process.env.FCM_PROJECT_ID || ''
  const clientEmail = process.env.FCM_CLIENT_EMAIL || ''
  const privateKey = normaliseKey(process.env.FCM_PRIVATE_KEY || '')
  if (!projectId || !clientEmail || !privateKey) return null
  return { projectId, clientEmail, privateKey }
}

// Settings are read per-push, so cache them. Short TTL: the admin expects a
// credential paste to take effect without a restart.
const CREDS_CACHE_TTL_MS = 60_000
let cachedCreds: { value: Creds | null; expiresAt: number } | null = null

async function credentials(): Promise<Creds | null> {
  const fromEnv = envCreds()
  if (fromEnv) return fromEnv

  const now = Date.now()
  if (cachedCreds && cachedCreds.expiresAt > now) return cachedCreds.value

  const fromBlock = (f: any): Creds | null => {
    const projectId = (f?.projectId || '').trim()
    const clientEmail = (f?.clientEmail || '').trim()
    const privateKey = normaliseKey(f?.privateKey || '')
    return projectId && clientEmail && privateKey ? { projectId, clientEmail, privateKey } : null
  }

  let value: Creds | null = null
  try {
    await connectDB()
    const s: any = await Settings.findOne({ key: 'global' }).select('firebase').lean()
    value = fromBlock(s?.firebase)
  } catch (e) {
    console.error('[push] could not read firebase settings from db', e)
    // Do not cache a lookup failure, so a transient DB blip cannot pin push off
    // for a minute.
    return null
  }

  // This project keeps settings in two places: /api/settings writes Mongo, while
  // lib/settings.ts reads data/settings.json (which is what the Maps key is
  // actually read from). Check the file too, so credentials work whichever store
  // they were saved into rather than silently doing nothing.
  if (!value) {
    try {
      const { getSettings } = await import('./settings')
      value = fromBlock((getSettings() as any)?.firebase)
    } catch {
      // No settings file, or unreadable — the Mongo result stands.
    }
  }

  cachedCreds = { value, expiresAt: now + CREDS_CACHE_TTL_MS }
  return value
}

/** True when a usable service account is configured from either source. */
export async function isPushConfigured(): Promise<boolean> {
  return (await credentials()) !== null
}

// ── OAuth token, cached until shortly before expiry ──
let cachedToken: { value: string; expiresAt: number } | null = null

function b64url(input: Buffer | string): string {
  return Buffer.from(input).toString('base64url')
}

async function accessToken(creds: Creds, force = false): Promise<string | null> {
  const now = Date.now()
  if (!force && cachedToken && cachedToken.expiresAt > now + 60_000) return cachedToken.value

  try {
    const iat = Math.floor(now / 1000)
    const claim = {
      iss: creds.clientEmail,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat,
      exp: iat + 3600,
    }
    const unsigned = `${b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64url(JSON.stringify(claim))}`
    const signature = crypto.createSign('RSA-SHA256').update(unsigned).sign(creds.privateKey)
    const assertion = `${unsigned}.${signature.toString('base64url')}`

    const res = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }),
    })
    const data = await res.json()
    if (!data.access_token) {
      console.error('[push] token exchange failed', data.error_description || data.error)
      return null
    }
    cachedToken = { value: data.access_token, expiresAt: now + (data.expires_in || 3600) * 1000 }
    return cachedToken.value
  } catch (e) {
    console.error('[push] token error', e)
    return null
  }
}

/**
 * Sends to one device token. Resolves false on any failure — a push must never
 * break the request that triggered it.
 *
 * Returns 'stale' when FCM reports the token is dead, so the caller can clear
 * it off the Driver/User document.
 */
export async function sendPush(
  token: string | null | undefined,
  msg: PushMessage,
): Promise<'sent' | 'stale' | 'skipped'> {
  if (!token) return 'skipped'
  const creds = await credentials()
  if (!creds) return 'skipped'
  const auth = await accessToken(creds)
  if (!auth) return 'skipped'

  try {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${creds.projectId}/messages:send`,
      {
        method: 'POST',
        headers: { Authorization: `Bearer ${auth}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: msg.title, body: msg.body },
            data: msg.data || {},
            android: {
              priority: 'HIGH',
              notification: {
                channel_id: msg.channelId || 'ride_requests',
                sound: 'default',
              },
            },
            apns: {
              headers: { 'apns-priority': '10' },
              payload: { aps: { sound: 'default', 'content-available': 1 } },
            },
          },
        }),
      },
    )
    if (res.ok) return 'sent'
    const err = await res.json().catch(() => ({}))
    const status = err?.error?.details?.[0]?.errorCode || err?.error?.status
    if (status === 'UNREGISTERED' || status === 'INVALID_ARGUMENT') return 'stale'
    console.error('[push] send failed', res.status, status)
    return 'skipped'
  } catch (e) {
    console.error('[push] send error', e)
    return 'skipped'
  }
}

/** Fire-and-forget helper for request paths that must not wait on delivery. */
export function sendPushAsync(token: string | null | undefined, msg: PushMessage): void {
  void sendPush(token, msg).catch(() => {})
}

// ── Addressed helpers ────────────────────────────────────────────────────────
// Every caller previously had to load the document, dig out .fcmToken and pass
// it in, and nothing ever acted on the 'stale' result — so a token from a
// reinstalled app stayed on the record forever and every later push to that
// person silently failed. These wrap both halves.

async function pushToDoc(
  Model: any,
  id: any,
  msg: PushMessage,
): Promise<'sent' | 'stale' | 'skipped'> {
  if (!id) return 'skipped'
  try {
    await connectDB()
    const doc: any = await Model.findById(id).select('fcmToken').lean()
    const token = doc?.fcmToken
    if (!token) return 'skipped'
    const result = await sendPush(token, msg)
    // FCM says this device is gone — drop it so we stop paying for the call and
    // so a future token for the same person is not shadowed by a dead one.
    if (result === 'stale') {
      await Model.updateOne({ _id: id }, { $unset: { fcmToken: 1 } }).catch(() => {})
    }
    return result
  } catch (e) {
    console.error('[push] addressed send failed', e)
    return 'skipped'
  }
}

/** Push to a driver by id, clearing the token if FCM reports it dead. */
export async function pushToDriver(driverId: any, msg: PushMessage) {
  const { default: Driver } = await import('@/models/Driver')
  return pushToDoc(Driver, driverId, msg)
}

/** Push to a rider by id, clearing the token if FCM reports it dead. */
export async function pushToUser(userId: any, msg: PushMessage) {
  const { default: User } = await import('@/models/User')
  return pushToDoc(User, userId, msg)
}

// ── Verification ─────────────────────────────────────────────────────────────
/**
 * Proves the configured service account actually works, by doing a real OAuth
 * exchange against Google rather than just checking the fields are non-empty.
 *
 * Exists because the admin's "Test Notification" button used to be a 1.5 s
 * setTimeout that always reported success — the one control an operator would
 * use to confirm push was live told them it was, whether or not it was.
 *
 * Pass a device token to also send a real notification to it.
 */
export async function verifyPushCredentials(token?: string): Promise<{
  ok: boolean
  source: 'env' | 'settings' | 'none'
  message: string
  delivered?: 'sent' | 'stale' | 'skipped'
}> {
  const source: 'env' | 'settings' | 'none' = envCreds() ? 'env' : 'settings'
  const creds = await credentials()
  if (!creds) {
    return {
      ok: false,
      source: 'none',
      message: 'No Firebase service account configured. Fill in Project ID, Client Email and Private Key (or set the FCM_* environment variables).',
    }
  }

  // force=true so a freshly pasted key is actually exercised rather than the
  // previous key's still-valid cached token being reported as success.
  const auth = await accessToken(creds, true)
  if (!auth) {
    return {
      ok: false,
      source,
      message: 'Google rejected these credentials. Check that the private key was pasted whole and matches this client email.',
    }
  }

  if (!token) {
    return {
      ok: true,
      source,
      message: `Credentials valid for project "${creds.projectId}" (from ${source === 'env' ? 'environment' : 'admin settings'}). Push is live.`,
    }
  }

  const delivered = await sendPush(token, {
    title: 'Gora test notification',
    body: 'Push notifications are working.',
    channelId: 'ride_updates',
    data: { type: 'test' },
  })
  return {
    ok: delivered === 'sent',
    source,
    delivered,
    message: delivered === 'sent'
      ? 'Test notification delivered to that device.'
      : delivered === 'stale'
      ? 'Credentials are valid, but that device token is no longer registered.'
      : 'Credentials are valid, but the send was rejected.',
  }
}

/** Fire-and-forget variants for request paths that must not wait on delivery. */
export function pushToDriverAsync(driverId: any, msg: PushMessage): void {
  void pushToDriver(driverId, msg).catch(() => {})
}
export function pushToUserAsync(userId: any, msg: PushMessage): void {
  void pushToUser(userId, msg).catch(() => {})
}

import crypto from 'crypto'
import jwt from 'jsonwebtoken'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import Driver from '@/models/Driver'
import Admin from '@/models/Admin'

const JWT_SECRET = process.env.JWT_SECRET!

/** Rider/driver tokens live 7 days and are renewed by POST /api/auth/refresh.
 *  Admin tokens are shorter-lived — pass ADMIN_TOKEN_TTL from the admin login. */
export const ADMIN_TOKEN_TTL = '12h'
export const ADMIN_TOKEN_TTL_SECONDS = 12 * 60 * 60
export const APP_TOKEN_TTL_SECONDS = 7 * 24 * 60 * 60

export function signToken(payload: object, expiresIn: string | number = '7d') {
  return jwt.sign(payload, JWT_SECRET, { expiresIn } as jwt.SignOptions)
}

export function verifyToken(token: string) {
  return jwt.verify(token, JWT_SECRET)
}

export function getTokenFromRequest(req: NextRequest) {
  const auth = req.headers.get('authorization')
  if (auth?.startsWith('Bearer ')) return auth.slice(7)
  return req.cookies.get('admin_token')?.value || null
}

export function getDriverTokenFromRequest(req: NextRequest) {
  const auth = req.headers.get('authorization')
  if (auth?.startsWith('Bearer ')) return auth.slice(7)
  return req.cookies.get('driver_token')?.value || null
}

export function requireAuth(req: NextRequest) {
  const token = getTokenFromRequest(req)
  if (!token) return null
  try { return verifyToken(token) } catch { return null }
}

/** Driver-app callers only: the payload must be typed 'driver'. Rider, admin and
 *  zone-admin tokens share the secret and are rejected here — admin tooling must
 *  use requireAdmin / guardAdmin instead. Signature only: money and account
 *  routes must use requireActiveDriver, which also refuses blocked, deleted and
 *  revoked sessions. */
export function requireDriverAuth(req: NextRequest) {
  const token = getDriverTokenFromRequest(req)
  if (!token) return null
  try {
    const p = verifyToken(token) as any
    return p?.type === 'driver' && p?.id ? p : null
  } catch { return null }
}

/** Rider-app callers only: the payload must be typed 'user'. Signature only —
 *  see requireActiveRider. */
export function requireRider(req: NextRequest) {
  const auth = req.headers.get('authorization')
  const token = auth?.startsWith('Bearer ') ? auth.slice(7) : null
  if (!token) return null
  try {
    const p = verifyToken(token) as any
    return p?.type === 'user' && p?.id ? p : null
  } catch { return null }
}

// ─────────────────────────────────────────────────────────────────────────────
// Account state behind a token (riders, drivers, admins).
//
// A JWT stays valid until it expires, so blocking or deleting an account did
// nothing to sessions already open. Every account now has `tokenVersion`; new
// tokens carry it as `tv` and are refused once the account's version moves on
// (soft delete, block, logout / log out everywhere). Tokens issued before this
// change have no `tv` and are accepted only while the account is still at
// version 0, i.e. until the first revocation.
//
// The lookup is cached per id for ACCOUNT_CACHE_MS. Revocations made by this
// process call invalidateAccountCache, so they apply on the very next request;
// a change made by another process applies within the cache window.
// ─────────────────────────────────────────────────────────────────────────────

export const ACCOUNT_CACHE_MS = 30_000
type AccountKind = 'rider' | 'driver' | 'admin'
type AccountState = { status: string; tv: number; exists: boolean; at: number }
const accountCache = new Map<string, AccountState>()

export function invalidateAccountCache(kind: AccountKind, id: string) {
  accountCache.delete(`${kind}:${id}`)
}

async function loadAccount(kind: AccountKind, id: string): Promise<AccountState> {
  const key = `${kind}:${id}`
  const hit = accountCache.get(key)
  if (hit && Date.now() - hit.at < ACCOUNT_CACHE_MS) return hit
  await connectDB()
  const Model: any = kind === 'driver' ? Driver : kind === 'rider' ? User : Admin
  let doc: any = null
  try { doc = await Model.findById(id).select('status tokenVersion').lean() } catch { doc = null }
  const st: AccountState = { status: String(doc?.status || 'active'), tv: Number(doc?.tokenVersion || 0), exists: !!doc, at: Date.now() }
  accountCache.set(key, st)
  if (accountCache.size > 20_000) {
    const cutoff = Date.now() - ACCOUNT_CACHE_MS
    for (const [k, v] of accountCache) if (v.at < cutoff) accountCache.delete(k)
  }
  return st
}

/** A token's tv must match the account; a token without tv only matches 0. */
function tvMatches(payload: any, accountTv: number): boolean {
  const tokenTv = payload?.tv
  if (tokenTv === undefined || tokenTv === null) return accountTv === 0
  return Number(tokenTv) === accountTv
}

export type ActiveCode = 'UNAUTHORIZED' | 'ACCOUNT_BLOCKED' | 'ACCOUNT_DELETED' | 'SESSION_REVOKED'
export type ActiveOk = { ok: true; id: string; payload: any; status: string; tv: number }
export type ActiveDenied = { ok: false; status: 401 | 403; code: ActiveCode; error: string }
export type ActiveResult = ActiveOk | ActiveDenied

const DENY: Record<Exclude<ActiveCode, 'UNAUTHORIZED'>, ActiveDenied> = {
  ACCOUNT_BLOCKED: { ok: false, status: 403, code: 'ACCOUNT_BLOCKED', error: 'Your account is blocked. Please contact support.' },
  ACCOUNT_DELETED: { ok: false, status: 403, code: 'ACCOUNT_DELETED', error: 'This account has been deleted.' },
  // 401, not 403: the app should drop the token and sign in again.
  SESSION_REVOKED: { ok: false, status: 401, code: 'SESSION_REVOKED', error: 'Your session has ended. Please sign in again.' },
}
const UNAUTH: ActiveDenied = { ok: false, status: 401, code: 'UNAUTHORIZED', error: 'Unauthorized' }

async function checkActive(kind: 'rider' | 'driver', p: any): Promise<ActiveResult> {
  if (!p?.id) return UNAUTH
  const a = await loadAccount(kind, String(p.id))
  if (!a.exists) return UNAUTH
  if (a.status === 'deleted') return DENY.ACCOUNT_DELETED
  if (a.status === 'blocked') return DENY.ACCOUNT_BLOCKED
  if (!tvMatches(p, a.tv)) return DENY.SESSION_REVOKED
  return { ok: true, id: String(p.id), payload: p, status: a.status, tv: a.tv }
}

/**
 * Rider token AND an account that is still usable: not deleted, not blocked,
 * session not revoked. Use on every money / booking / account route.
 *     const a = await requireActiveRider(req); if (!a.ok) return activeDenied(a)
 */
export async function requireActiveRider(req: NextRequest): Promise<ActiveResult> {
  return checkActive('rider', requireRider(req))
}

/** Driver counterpart of requireActiveRider. A 'pending'/'rejected' driver is
 *  still "active" here (registration needs it) — check approval separately. */
export async function requireActiveDriver(req: NextRequest): Promise<ActiveResult> {
  return checkActive('driver', requireDriverAuth(req))
}

/** JSON response for a denied requireActive* result. `code` tells the app why:
 *  ACCOUNT_BLOCKED / ACCOUNT_DELETED (403) or SESSION_REVOKED / UNAUTHORIZED (401). */
export function activeDenied(a: ActiveDenied) {
  return NextResponse.json({ error: a.error, code: a.code }, { status: a.status })
}

/** Revoke every token of a rider/driver/admin: bump tokenVersion. */
export async function bumpTokenVersion(kind: AccountKind, id: string) {
  await connectDB()
  const Model: any = kind === 'driver' ? Driver : kind === 'rider' ? User : Admin
  await Model.updateOne({ _id: id }, { $inc: { tokenVersion: 1 } })
  invalidateAccountCache(kind, String(id))
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin tokens. New ones are typed 'admin' and carry `tv`. Untyped tokens were
// issued by the old login; they are accepted only while they are within the
// 12 h admin lifetime (exp - iat) and the admin is still at tokenVersion 0.
// Rider ('user'), driver and zone admin tokens share the secret and are never
// admins.
// ─────────────────────────────────────────────────────────────────────────────

export function isAdminPayload(p: any): boolean {
  if (!p?.id) return false
  if (p.type === 'admin') return true
  if (p.type) return false
  // Legacy untyped token: only a short-lived one, as the old admin login signed.
  const iat = Number(p.iat || 0), exp = Number(p.exp || 0)
  return !!iat && !!exp && exp - iat <= ADMIN_TOKEN_TTL_SECONDS
}

export function signAdminToken(admin: { _id: any; email: string; role?: string; tokenVersion?: number }) {
  return signToken({ id: String(admin._id), email: admin.email, role: admin.role || 'admin', type: 'admin', tv: Number(admin.tokenVersion || 0) }, ADMIN_TOKEN_TTL)
}

/**
 * Signature-only admin check (sync). It also refuses a token this process
 * already knows to be revoked (cached state), but only requireActiveAdmin /
 * guardAdmin are authoritative — use those as the gate.
 */
export function requireAdmin(req: NextRequest) {
  const p = requireAuth(req) as any
  if (!isAdminPayload(p)) return null
  const cached = accountCache.get(`admin:${p.id}`)
  if (cached && (!cached.exists || !tvMatches(p, cached.tv))) return null
  return p
}

/** Admin token whose account still exists and whose session is not revoked. */
export async function requireActiveAdmin(req: NextRequest): Promise<any | null> {
  const p = requireAdmin(req)
  if (!p) return null
  const a = await loadAccount('admin', String(p.id))
  if (!a.exists || !tvMatches(p, a.tv)) return null
  return p
}

// ── Sliding sessions for the apps (POST /api/auth/refresh) ──
/** A rider/driver token may be exchanged for a fresh 7-day one once it is this old. */
export const REFRESH_MIN_AGE_SECONDS = 24 * 60 * 60

/** ISO time from which the app may refresh this token, or null if unknown. */
export function refreshAfterOf(p: any): string | null {
  const iat = Number(p?.iat || 0)
  return iat ? new Date((iat + REFRESH_MIN_AGE_SECONDS) * 1000).toISOString() : null
}

/** Constant-time comparison of a presented secret (cron header etc.) with the
 *  expected one. Both are hashed first, so length differences leak nothing and
 *  multi-byte input can't throw. False when `expected` is empty. */
export function secretEquals(presented: string | null | undefined, expected: string | null | undefined): boolean {
  if (!expected) return false
  const a = crypto.createHash('sha256').update(String(presented ?? '')).digest()
  const b = crypto.createHash('sha256').update(String(expected)).digest()
  return crypto.timingSafeEqual(a, b)
}

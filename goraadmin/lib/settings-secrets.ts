// Secrets inside the Settings document are never sent to the browser in full.
// GET handlers mask them as MASK_PREFIX + last 4 characters; when the panel posts
// the form back unchanged, a masked value is swapped for the stored one, so
// saving another field never overwrites a real key with its mask.
export const MASK_PREFIX = '••••'

/** Dotted paths relative to the Settings document. */
export const SECRET_PATHS = [
  'payment.razorpay.keySecret',
  'payment.razorpay.testKeySecret',
  'payment.razorpay.liveKeySecret',
  'payment.razorpay.webhookSecret',
  'payment.stripe.secretKey',
  'sms.smsindori.authKey',
  'sms.msg91.authKey',
  'sms.twilio.authToken',
  'firebase.serverKey',
  'firebase.privateKey',
  'maps.googleMapsApiKey',
  'mail.password',
]

export function maskSecret(v: unknown): unknown {
  if (typeof v !== 'string' || !v) return v
  return MASK_PREFIX + (v.length > 8 ? v.slice(-4) : '')
}

export function isMasked(v: unknown): boolean {
  return typeof v === 'string' && v.startsWith(MASK_PREFIX)
}

function get(o: any, parts: string[]) {
  return parts.reduce((a, k) => (a && typeof a === 'object' ? a[k] : undefined), o)
}

function clone<T>(o: T): T {
  return o === undefined ? o : JSON.parse(JSON.stringify(o))
}

function relParts(p: string, prefix: string): string[] | null {
  if (!prefix) return p.split('.')
  return p.startsWith(prefix + '.') ? p.slice(prefix.length + 1).split('.') : null
}

/** Copy of `doc` with every secret masked. `prefix` = path of `doc` inside
 *  Settings (e.g. 'payment' when masking just the payment block). */
export function maskSettings(doc: any, prefix = ''): any {
  if (!doc || typeof doc !== 'object') return doc
  const out = clone(doc)
  for (const p of SECRET_PATHS) {
    const parts = relParts(p, prefix); if (!parts) continue
    const parent = get(out, parts.slice(0, -1))
    const last = parts[parts.length - 1]
    if (parent && typeof parent === 'object' && typeof parent[last] === 'string' && parent[last]) {
      parent[last] = maskSecret(parent[last])
    }
  }
  return out
}

/** Replaces any masked secret in `incoming` with the value stored in `current`
 *  (same shape / prefix). Mutates and returns `incoming`. */
export function unmaskSettings(incoming: any, current: any, prefix = ''): any {
  if (!incoming || typeof incoming !== 'object') return incoming
  for (const p of SECRET_PATHS) {
    const parts = relParts(p, prefix); if (!parts) continue
    const parent = get(incoming, parts.slice(0, -1))
    const last = parts[parts.length - 1]
    if (parent && typeof parent === 'object' && isMasked(parent[last])) {
      const real = get(current, parts)
      parent[last] = typeof real === 'string' ? real : ''
    }
  }
  return incoming
}

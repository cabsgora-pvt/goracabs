import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import AdminAudit from '@/models/AdminAudit'
import { clientIp } from '@/lib/rate-limit'

// ─────────────────────────────────────────────────────────────────────────────
// Admin audit log. guardAdmin calls auditRequest() for every non-GET admin API
// call (a generic 'api.<METHOD>' row). A route that knows more calls
//     await auditAdmin(req, admin, 'driver.wallet.adjust', { target, summary, details })
// which fills in that same row (one row per request), or inserts one when the
// route did not go through guardAdmin. Never throws: an audit failure must not
// fail the admin's action. Never put passwords, tokens or bank numbers in it.
// ─────────────────────────────────────────────────────────────────────────────

type Details = { target?: string; summary?: string; details?: unknown }
const pending = new WeakMap<NextRequest, Promise<any>>()

const SECRET_KEYS = /pass(word)?|token|secret|otp|accountnumber|account_number|ifsc|cvv|pin/i

/** Drop secret-looking keys and cap the size of whatever a route records. */
export function scrub(v: unknown, depth = 0): unknown {
  if (v === null || v === undefined) return v
  if (typeof v === 'string') return v.length > 300 ? v.slice(0, 300) + '…' : v
  if (typeof v !== 'object') return v
  if (depth > 3) return '[…]'
  if (Array.isArray(v)) return v.slice(0, 20).map(x => scrub(x, depth + 1))
  const out: Record<string, unknown> = {}
  for (const [k, x] of Object.entries(v as Record<string, unknown>).slice(0, 40)) {
    out[k] = SECRET_KEYS.test(k) ? '[redacted]' : scrub(x, depth + 1)
  }
  return out
}

function base(req: NextRequest, admin: any) {
  return {
    adminId: admin?.id && /^[a-f0-9]{24}$/i.test(String(admin.id)) ? admin.id : undefined,
    email: admin?.email || '',
    method: req.method,
    path: req.nextUrl?.pathname || '',
    ip: clientIp(req),
    at: new Date(),
  }
}

/** Generic row for a non-GET admin request (called by guardAdmin). */
export function auditRequest(req: NextRequest, admin: any) {
  if (req.method === 'GET' || req.method === 'HEAD' || req.method === 'OPTIONS') return
  const p = (async () => {
    try {
      await connectDB()
      return await AdminAudit.create({ ...base(req, admin), action: `api.${req.method}` })
    } catch { return null }
  })()
  pending.set(req, p)
}

export async function auditAdmin(req: NextRequest, admin: any, action: string, d: Details = {}) {
  try {
    const fields: any = { action, target: d.target ? String(d.target).slice(0, 120) : undefined, summary: d.summary ? String(d.summary).slice(0, 300) : undefined }
    if (d.details !== undefined) fields.details = scrub(d.details)
    const row = await pending.get(req)
    await connectDB()
    if (row?._id) {
      await AdminAudit.updateOne({ _id: row._id }, { $set: fields })
    } else {
      const created = await AdminAudit.create({ ...base(req, admin), ...fields })
      pending.set(req, Promise.resolve(created))
    }
  } catch { /* never fail the request */ }
}

/** Like auditAdmin, recording the request's JSON body (scrubbed) as details.
 *  Reads a clone, so the route can still read the body itself. */
export async function auditAdminBody(req: NextRequest, admin: any, action: string, target?: string) {
  let body: unknown
  try {
    if ((req.headers.get('content-type') || '').includes('application/json')) body = await req.clone().json()
  } catch { body = undefined }
  await auditAdmin(req, admin, action, { target, details: body })
}

import { NextRequest, NextResponse } from 'next/server'
import { requireAuth, requireDriverAuth, requireAdmin, isAdminPayload } from './auth'

// ─────────────────────────────────────────────────────────────────────────────
// Admin-only API guard.
//
// middleware.ts returns early for every /api/* path — it attaches CORS headers
// and nothing else — so the admin dashboard's own endpoints shipped with NO
// authentication at all. /api/drivers/{id}/approve would approve any driver for
// any caller, and /api/drivers/{id}/wallet would credit any driver any amount
// and write a matching Transaction. CORS echoes the caller's Origin with
// credentials allowed, so these were reachable from any web page.
//
// This cannot live in middleware on Next 14: middleware runs on the Edge
// runtime and the admin token is verified with `jsonwebtoken`, which needs
// Node. So the guard is explicit, per route, and returns a response the handler
// returns straight back.
//
// Usage, as the first line inside the handler:
//     const denied = guardAdmin(req); if (denied) return denied
// ─────────────────────────────────────────────────────────────────────────────

/** Returns a 401 response when the caller is not a signed-in admin, else null. */
export function guardAdmin(req: NextRequest): NextResponse | null {
  if (requireAdmin(req)) return null
  return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
}

/**
 * Ride-scoped guard: the caller must be the rider on this ride, its assigned
 * driver, or an admin. Use on the per-ride action routes, which shipped with no
 * auth at all — any caller who knew a ride id could cancel it, rate it, advance
 * its phase or flag it awaiting payment.
 *
 * Returns null when allowed, else a 401/403 response to return directly.
 */
export function guardRideActor(
  req: NextRequest,
  ride: { riderId?: any; driverId?: any },
): NextResponse | null {
  const asDriver = requireDriverAuth(req) as any
  const asUser = requireAuth(req) as any
  if (!asDriver?.id && !asUser?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  const isDriver = !!asDriver?.id && !!ride.driverId && String(ride.driverId) === String(asDriver.id)
  const isRider = !!asUser?.id && !!ride.riderId && String(ride.riderId) === String(asUser.id)
  // An admin token also satisfies requireAuth but will not match riderId; allow
  // it explicitly so support staff can act on a ride from the dashboard.
  const isAdmin = isAdminPayload(asUser) && req.headers.get('x-admin-override') === '1'
  if (isDriver || isRider || isAdmin) return null
  return NextResponse.json({ error: 'Not a participant in this ride' }, { status: 403 })
}

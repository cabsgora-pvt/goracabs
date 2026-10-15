// ─────────────────────────────────────────────────────────────────────────────
// One computed phase for a ride.
//
// A ride's real state is spread across five fields — `status`, plus whichever of
// `rentalPhase` / `hirePhase` / `deliveryPhase` applies, plus `awaitingPayment`.
// Every client that wants to show "what is happening right now" has to re-derive
// it from all five, and two apps deriving the same thing independently will
// eventually disagree — usually at the edges, which is exactly where a rider is
// watching most closely.
//
// So it is computed once, here, and returned to the clients as `uiPhase`. The
// underlying fields are still sent, so nothing that reads them today breaks.
// ─────────────────────────────────────────────────────────────────────────────

export type UiPhase =
  | 'finding'    // no driver yet — searching
  | 'assigned'   // driver accepted, travelling to pickup
  | 'arrived'    // driver is at the pickup point, waiting
  | 'ongoing'    // trip / rental / hire / delivery under way
  | 'payment'    // work done, waiting for the rider to pay
  | 'completed'
  | 'cancelled'

export type UiPhaseInfo = {
  phase: UiPhase
  /// Short human label. Service-aware, because "On trip" is wrong for a parcel.
  label: string
  /// True when the customer is being charged beyond what they booked, so the
  /// client can colour the state without knowing each service's own vocabulary.
  overrun: boolean
}

export function uiPhaseFor(ride: any): UiPhaseInfo {
  const status = String(ride?.status || 'pending')
  const service = String(ride?.service || 'taxi')

  if (status === 'cancelled') return { phase: 'cancelled', label: 'Cancelled', overrun: false }
  if (status === 'completed') return { phase: 'completed', label: 'Completed', overrun: false }

  // Payment is checked before the in-progress states: the driver has finished
  // and is standing there waiting to be paid, which is what the rider must act
  // on, whatever the service-specific phase still says.
  if (ride?.awaitingPayment) return { phase: 'payment', label: 'Payment due', overrun: false }

  if (status === 'pending') return { phase: 'finding', label: 'Finding a driver', overrun: false }
  if (status === 'accepted') return { phase: 'assigned', label: 'Driver on the way', overrun: false }
  if (status === 'arrived') return { phase: 'arrived', label: 'Driver has arrived', overrun: false }

  // ── ongoing: the label and the overrun flag are service-specific ──
  if (service === 'rental') {
    const p = String(ride?.rentalPhase || '')
    if (p === 'paused') return { phase: 'ongoing', label: 'Waiting', overrun: false }
    if (p === 'extra_time') return { phase: 'ongoing', label: 'Extra time', overrun: true }
    return { phase: 'ongoing', label: 'Rental in progress', overrun: false }
  }
  if (service === 'hire_driver') {
    const p = String(ride?.hirePhase || '')
    if (p === 'overtime') return { phase: 'ongoing', label: 'Overtime', overrun: true }
    return { phase: 'ongoing', label: 'Driver on duty', overrun: false }
  }
  if (service === 'delivery') {
    const p = String(ride?.deliveryPhase || '')
    if (p === 'returned' || p === 'failed') {
      return { phase: 'ongoing', label: 'Returning to sender', overrun: false }
    }
    if (p === 'in_transit' || p === 'collected') {
      return { phase: 'ongoing', label: 'Out for delivery', overrun: false }
    }
    return { phase: 'ongoing', label: 'Collecting parcel', overrun: false }
  }

  return { phase: 'ongoing', label: 'On trip', overrun: false }
}

/**
 * Seconds the driver has been waiting at pickup, computed on the SERVER.
 *
 * Clients count up locally from this value rather than doing
 * `deviceNow - arrivedAt` themselves. That subtraction mixes the server's clock
 * with the phone's, and phone clocks are routinely minutes off — the result is
 * a waiting timer that starts negative, or already at twelve minutes. Anchoring
 * on a server-computed elapsed value keeps both ends of the measurement on one
 * clock, so device skew cancels out.
 *
 * Null when the driver is not currently waiting.
 */
export function waitingSecondsFor(ride: any): number | null {
  if (ride?.status !== 'arrived' || !ride?.arrivedAt) return null
  return secondsSince(ride.arrivedAt)
}

/**
 * Whole seconds from [since] to now, on the SERVER's clock, or null when
 * [since] is missing or unparseable. For the same reason as waitingSecondsFor:
 * a client timer that subtracts a server timestamp from its own clock inherits
 * the phone's error, so a rental clock could open reading minutes off.
 */
export function secondsSince(since: any): number | null {
  if (!since) return null
  const ms = Date.now() - new Date(since).getTime()
  return Number.isFinite(ms) ? Math.max(0, Math.floor(ms / 1000)) : null
}

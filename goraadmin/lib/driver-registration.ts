// Registration lock: what a driver may still change about themselves.
//
// Zone (which rides and which franchise), gender (female-preference rides),
// vehicle type / plate and verified documents are checked by an admin at
// approval. Once the registration is under review or approved they can no
// longer be changed from the driver app — a zone move goes through
// auth/driver/account-request (kind 'zone_change'), anything else through
// support. A REJECTED driver is unlocked again so they can fix and resubmit.
export function registrationLocked(d: any): boolean {
  if (!d) return false
  if (['approved', 'blocked', 'deleted'].includes(d.status)) return true
  return d.registrationStep === 'submitted' && d.status === 'pending'
}

export const LOCKED_CODE = 'REGISTRATION_LOCKED'

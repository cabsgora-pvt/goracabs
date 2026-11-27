// Admin-side "does this driver's vehicle meet its type's rules" check
// (lib/vehicle-tiers eligibilityProblems), for the driver detail and pending
// approval screens. Advisory only: approval is never blocked by it.

import VehicleType from '@/models/VehicleType'
import { eligibilityProblems, requirementsOf, requirementsText } from '@/lib/vehicle-tiers'

export type VehicleCheck = { type: string | null; problems: string[]; rules: string }

/** Loads every vehicle type once and returns a name → type lookup (exact name first, then case-insensitive). */
export async function loadVehicleTypeLookup(): Promise<(name: any) => any | null> {
  const all: any[] = await VehicleType.find().select('name category rank requirements isActive').lean()
  const exact = new Map<string, any>(), loose = new Map<string, any>()
  for (const t of all) {
    const n = String(t.name || '')
    if (!n) continue
    if (!exact.has(n)) exact.set(n, t)
    const k = n.trim().toLowerCase()
    if (!loose.has(k)) loose.set(k, t)
  }
  return (name: any) => {
    const n = String(name || '')
    if (!n) return null
    return exact.get(n) || loose.get(n.trim().toLowerCase()) || null
  }
}

/** The check for one driver: their type (null when it has none / it no longer exists), the problems, the type's rules. */
export function vehicleCheckOf(findType: (name: any) => any | null, d: any): VehicleCheck {
  const vt = findType(d?.selectedVehicleTypeName || d?.vehicleType)
  if (!vt) return { type: null, problems: [], rules: '' }
  return {
    type: String(vt.name),
    problems: eligibilityProblems(vt, { vehicleModel: d?.vehicleModel, vehicleYear: d?.vehicleYear, rating: d?.rating }),
    rules: requirementsText(requirementsOf(vt)),
  }
}

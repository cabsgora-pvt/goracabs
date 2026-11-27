// Browser-safe twin of the name inference in lib/vehicle-tiers.ts (that file
// imports the VehicleType model, so admin pages cannot bundle it). Used by the
// vehicle types page to show what "Auto-detect from name" would pick, and by
// the driver pages to work out lower tiers from GET /api/vehicles/types.
// Keep the two regex sets identical — tiersAdmin-test compares them.

export const CATEGORY_OPTIONS: { value: string; label: string }[] = [
  { value: 'bike', label: 'Bike' },
  { value: 'scooter', label: 'Scooter' },
  { value: 'auto', label: 'Auto' },
  { value: 'cab', label: 'Cab' },
  { value: 'truck', label: 'Truck' },
  { value: 'other', label: 'Other' },
]

export function guessCategory(name: any): string {
  const n = String(name || '').toLowerCase()
  if (/truck|tempo|loader|cargo|goods|pickup|\bace\b/.test(n)) return 'truck'
  if (/scoot/.test(n)) return 'scooter'
  if (/bike|moto|two.?wheel/.test(n)) return 'bike'
  if (/auto|rick/.test(n)) return 'auto'
  return 'cab'
}

export function guessRank(name: any): number {
  const n = String(name || '').toLowerCase()
  if (/suv|\bxl\b|innova|7.?seat|6.?seat/.test(n)) return 3
  if (/prime|premium|premier|sedan|luxury|comfort/.test(n)) return 2
  return 1
}

export function categoryLabel(c: string): string {
  const hit = CATEGORY_OPTIONS.find(o => o.value === c)
  return hit ? hit.label : (c ? c.charAt(0).toUpperCase() + c.slice(1) : 'Other')
}

/**
 * Lower tiers of a type, from the GET /api/vehicles/types list (each row
 * carries its effective category + rank): same category, lower rank, active.
 * Mirrors lowerTiersOf() in lib/vehicle-tiers.ts.
 */
export function lowerTierNames(types: any[], typeName: any): string[] {
  const active = (types || []).filter(t => t.isActive !== false)
  const own = active.find(t => String(t.name) === String(typeName || ''))
  if (!own) return []
  return active
    .filter(t => t.category === own.category && Number(t.rank) < Number(own.rank))
    .sort((a, b) => Number(a.rank) - Number(b.rank))
    .map(t => String(t.name))
}

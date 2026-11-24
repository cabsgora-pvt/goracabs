import DocumentType from '@/models/DocumentType'

export const DOC_CATEGORIES = ['identity', 'vehicle', 'driving', 'other'] as const
export const DOC_CATEGORY_LABEL: Record<string, string> = {
  identity: 'Identity', vehicle: 'Vehicle', driving: 'Driving licence', other: 'Other',
}

// The documents the driver app asked for before they became admin-managed.
export const DEFAULT_DOC_TYPES = [
  { key: 'aadhaar', name: 'Aadhaar Card', category: 'identity', numberLabel: 'Aadhaar Number', needsBack: true, needsExpiry: false, required: true, order: 1 },
  { key: 'pan', name: 'PAN Card', category: 'identity', numberLabel: 'PAN Number', needsBack: false, needsExpiry: false, required: true, order: 2 },
  { key: 'rc', name: 'RC Book', category: 'vehicle', numberLabel: 'RC Book Number', needsBack: false, needsExpiry: false, required: true, order: 3 },
  { key: 'insurance', name: 'Vehicle Insurance', category: 'vehicle', numberLabel: 'Insurance Number', needsBack: true, needsExpiry: true, required: true, order: 4 },
  { key: 'dl', name: 'Driving License', category: 'driving', numberLabel: 'License Number', needsBack: false, needsExpiry: false, required: true, order: 5 },
]

/** Seeds the default list once, so the app never sees an empty list. */
let categoriesFilled = false
export async function ensureDocTypes() {
  if (await DocumentType.estimatedDocumentCount() > 0) {
    // Rows seeded before document types had a category: give the five
    // defaults theirs, once per process (never overwrites an admin's choice).
    if (!categoriesFilled) {
      categoriesFilled = true
      await Promise.all(DEFAULT_DOC_TYPES.map(d =>
        DocumentType.updateOne({ key: d.key, category: { $exists: false } }, { $set: { category: d.category } }),
      )).catch(() => {})
    }
    return
  }
  await DocumentType.insertMany(DEFAULT_DOC_TYPES.map(d => ({ ...d, isActive: true }))).catch(() => {})
}

export function docTypeKey(name: string): string {
  return String(name || '').toLowerCase().trim().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40)
}

/** Does this document apply to a driver of `vehicleType`? */
export function appliesTo(d: any, vehicleType?: string | null): boolean {
  const list: string[] = (d.vehicleTypes || []).map((v: string) => String(v).toLowerCase())
  if (!list.length || !vehicleType) return true
  return list.includes(String(vehicleType).toLowerCase())
}

/** The shape both the app and the admin read. Old rows get the defaults. */
export function publicDocType(d: any) {
  return {
    id: String(d._id), _id: String(d._id), key: d.key, name: d.name,
    category: DOC_CATEGORIES.includes(d.category) ? d.category : 'other',
    description: d.description || '',
    needsNumber: d.needsNumber !== false,
    numberLabel: d.numberLabel || 'Document Number',
    frontLabel: d.frontLabel || 'Front side',
    backLabel: d.backLabel || 'Back side',
    needsBack: !!d.needsBack, needsExpiry: !!d.needsExpiry, required: d.required !== false,
    isActive: d.isActive !== false, order: d.order || 0,
    vehicleTypes: Array.isArray(d.vehicleTypes) ? d.vehicleTypes : [],
  }
}

/**
 * Cleans an admin's create/update body into DocumentType fields. Only keys
 * present in the body are returned (so a PUT can change one thing).
 */
export function docTypeFields(b: any): Record<string, any> {
  const out: Record<string, any> = {}
  const str = (k: string, max: number) => { if (typeof b[k] === 'string') out[k] = b[k].trim().slice(0, max) }
  if (typeof b.name === 'string' && b.name.trim()) out.name = b.name.trim().slice(0, 60)
  str('numberLabel', 60); str('frontLabel', 40); str('backLabel', 40); str('description', 400)
  if (out.numberLabel === '') out.numberLabel = 'Document Number'
  if (out.frontLabel === '') out.frontLabel = 'Front side'
  if (out.backLabel === '') out.backLabel = 'Back side'
  if (typeof b.category === 'string' && (DOC_CATEGORIES as readonly string[]).includes(b.category)) out.category = b.category
  for (const k of ['needsNumber', 'needsBack', 'needsExpiry', 'required', 'isActive']) if (typeof b[k] === 'boolean') out[k] = b[k]
  if (Array.isArray(b.vehicleTypes)) {
    out.vehicleTypes = Array.from(new Set(b.vehicleTypes.map((v: any) => String(v).trim()).filter(Boolean))).slice(0, 20)
  }
  if (b.order !== undefined && b.order !== '' && Number.isFinite(Number(b.order))) out.order = Number(b.order)
  return out
}

/**
 * Which required documents (for this vehicle type) are missing or incomplete
 * in what a driver submitted. Returns their keys and names.
 */
export async function missingRequiredDocs(submitted: any[], vehicleType?: string | null) {
  await ensureDocTypes()
  const types: any[] = await DocumentType.find({ isActive: true, required: { $ne: false } }).sort({ order: 1 }).lean()
  const byKey = new Map<string, any>()
  for (const s of submitted || []) if (s && s.type) byKey.set(String(s.type), s)
  const missing: { key: string; name: string }[] = []
  for (const t of types) {
    if (!appliesTo(t, vehicleType)) continue
    const s = byKey.get(t.key)
    const front = s && String(s.frontUrl || s.fileUrl || '').trim()
    const ok = !!s && !!front
      && (t.needsNumber === false || !!String(s.number || '').trim())
      && (!t.needsBack || !!String(s.backUrl || '').trim())
      && (!t.needsExpiry || !!String(s.expiryDate || '').trim())
    if (!ok) missing.push({ key: t.key, name: t.name })
  }
  return missing
}

'use client'
import { useState, useEffect, useRef } from 'react'
import { Header } from '@/components/header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { PageHeader } from '@/components/ui/page-header'
import { Plus, Pencil, Trash2, Upload, Car, ShieldCheck } from 'lucide-react'
import { CATEGORY_OPTIONS, guessCategory, guessRank, categoryLabel } from '@/lib/vehicle-tiers-client'

const THIS_YEAR = new Date().getFullYear()

const ALL_SERVICES = [
  { key: 'taxi',         label: 'Taxi / Cab Ride' },
  { key: 'rental',       label: 'Rental Package' },
  { key: 'outstation',   label: 'Outstation' },
  { key: 'delivery',     label: 'Parcel Delivery' },
  { key: 'hire_driver',  label: 'Hire a Driver' },
]

const defaultForm = {
  name: '', imageUrl: '', capacity: 4,
  baseFare: 50, perKm: 15, perMin: 2, minFare: 70,
  baseDistance: 2, waitingCharge: 1, isAcceptShareRide: false,
  services: ['taxi'],
  // Tier fields (lib/vehicle-tiers): '' = auto-detect from the name.
  category: '', rank: '', tagline: '',
  reqYear: '', reqRating: '', reqModels: '', reqNote: '',
}

/** Rows grouped by (effective) category, known categories first; lowest level first inside a group. */
function groupByCategory(types: any[]) {
  const order = CATEGORY_OPTIONS.map(o => o.value)
  const groups = new Map<string, any[]>()
  for (const t of types) {
    const c = String(t.category || 'other')
    if (!groups.has(c)) groups.set(c, [])
    groups.get(c)!.push(t)
  }
  const pos = (c: string) => { const i = order.indexOf(c); return i < 0 ? order.length : i }
  return Array.from(groups.entries())
    .sort(([a], [b]) => pos(a) - pos(b) || a.localeCompare(b))
    .map(([category, rows]) => ({
      category,
      label: rows[0]?.categoryLabel || categoryLabel(category),
      rows: rows.slice().sort((x, y) => (Number(x.rank) || 1) - (Number(y.rank) || 1)),
    }))
}

export default function VehicleTypesPage() {
  const [types, setTypes] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showModal, setShowModal] = useState(false)
  const [editItem, setEditItem] = useState<any>(null)
  const [form, setForm] = useState<any>(defaultForm)
  const [uploading, setUploading] = useState(false)
  const [preview, setPreview] = useState('')
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)

  const fetchTypes = () => {
    fetch('/api/vehicles/types')
      .then(r => r.json())
      .then(d => { setTypes(d.types || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchTypes() }, [])

  const openAdd = () => {
    setForm(defaultForm); setEditItem(null); setPreview(''); setShowModal(true)
  }

  const openEdit = (t: any) => {
    const f = {
      name: t.name, imageUrl: t.imageUrl || '', capacity: t.capacity,
      baseFare: t.baseFare, perKm: t.perKm, perMin: t.perMin, minFare: t.minFare,
      baseDistance: t.baseDistance ?? 2, waitingCharge: t.waitingCharge ?? 1,
      isAcceptShareRide: t.isAcceptShareRide ?? false,
      services: t.services?.length ? t.services : ['taxi'],
      // What the admin set ('' / null = auto) — not the inferred value, so an
      // untouched "auto" type stays auto (and follows a rename).
      category: t.storedCategory ?? '',
      rank: t.storedRank ?? '',
      tagline: t.tagline || '',
      reqYear: t.requirements?.minModelYear ?? '',
      reqRating: t.requirements?.minDriverRating ?? '',
      reqModels: (t.requirements?.allowedModels || []).join(', '),
      reqNote: t.requirements?.note || '',
    }
    setForm(f)
    setPreview(t.imageUrl || '')
    setEditItem(t)
    setShowModal(true)
  }

  const handleImageUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    setUploading(true)
    // Instant local preview
    const reader = new FileReader()
    reader.onload = ev => setPreview(ev.target?.result as string)
    reader.readAsDataURL(file)
    // Upload to server
    const fd = new FormData()
    fd.append('file', file)
    const res = await fetch('/api/upload', { method: 'POST', body: fd })
    const data = await res.json()
    if (data.url) {
      // Store relative path — browser resolves against current host (works on localhost + production)
      setForm((f: any) => ({ ...f, imageUrl: data.url }))
    }
    setUploading(false)
  }

  const toggleService = (key: string) => {
    setForm((f: any) => ({
      ...f,
      services: f.services.includes(key)
        ? f.services.filter((s: string) => s !== key)
        : [...f.services, key],
    }))
  }

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    const url = editItem ? `/api/vehicles/types/${editItem._id}` : '/api/vehicles/types'
    const { reqYear, reqRating, reqModels, reqNote, ...rest } = form
    // The server cleans these again (cleanTierFields): '' / null = not set.
    const body = {
      ...rest,
      category: form.category || '',
      rank: form.rank === '' || form.rank === null ? null : Number(form.rank),
      tagline: String(form.tagline || '').trim().slice(0, 80),
      requirements: {
        minModelYear: reqYear === '' || reqYear === null ? null : Number(reqYear),
        minDriverRating: reqRating === '' || reqRating === null ? null : Number(reqRating),
        allowedModels: String(reqModels || '').split(',').map((m: string) => m.trim()).filter(Boolean),
        note: String(reqNote || '').trim().slice(0, 200),
      },
    }
    try {
      const res = await fetch(url, {
        method: editItem ? 'PUT' : 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      })
      if (res.ok) {
        fetchTypes()
        setToast({ msg: editItem ? 'Updated' : 'Added', type: 'success' })
        setShowModal(false)
      } else {
        const d = await res.json().catch(() => ({}))
        setToast({ msg: d.error || 'Could not save', type: 'error' })
      }
    } catch (err: any) {
      // e.g. the password prompt was cancelled — nothing was saved.
      setToast({ msg: err?.message || 'Could not save', type: 'error' })
    }
  }

  const autoCategory = guessCategory(form.name)
  const autoRank = guessRank(form.name)
  const knownCategory = CATEGORY_OPTIONS.some(o => o.value === form.category)
  const groups = groupByCategory(types)

  const handleDelete = async (id: string) => {
    if (!confirm('Delete this vehicle type?')) return
    const res = await fetch(`/api/vehicles/types/${id}`, { method: 'DELETE' })
    if (res.ok) { fetchTypes(); setToast({ msg: 'Deleted', type: 'error' }) }
  }

  if (loading) return (
    <div><Header title="Vehicle Types" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  return (
    <div>
      <Header title="Vehicle Types" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="Vehicle Types"
          subtitle={`${types.length} vehicle types configured`}
          action={
            <button type="button" onClick={openAdd}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-lg text-sm font-medium hover:bg-primary-dark">
              <Plus className="w-4 h-4" /> Add Vehicle Type
            </button>
          }
        />

        {/* List / Table view */}
        <div className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-100">
                <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Vehicle</th>
                <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Seats</th>
                <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Base Fare</th>
                <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Per KM</th>
                <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Min Fare</th>
                <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Free KM</th>
                <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Services</th>
                <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {groups.map(g => [
                <tr key={`cat-${g.category}`} className="bg-gray-50/70">
                  <td colSpan={8} className="px-4 py-2 text-xs font-semibold text-gray-600 uppercase tracking-wide">
                    {g.label}
                    <span className="ml-2 font-normal normal-case tracking-normal text-gray-400">
                      {g.rows.length} type{g.rows.length === 1 ? '' : 's'}
                    </span>
                  </td>
                </tr>,
                ...g.rows.map(t => (
                <tr key={t._id} className="hover:bg-gray-50">
                  {/* Image + name */}
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-3">
                      <div className="w-12 h-10 rounded-lg bg-gray-50 border border-gray-100 flex items-center justify-center overflow-hidden flex-shrink-0">
                        {t.imageUrl
                          ? <img src={t.imageUrl} alt={t.name} className="w-full h-full object-contain p-0.5" />
                          : <Car className="w-6 h-6 text-gray-300" />
                        }
                      </div>
                      <div className="min-w-0">
                        <p className="font-semibold text-gray-900 flex items-center gap-2 flex-wrap">
                          {t.name}
                          <span className="px-2 py-0.5 bg-purple-50 text-purple-700 rounded-full text-[11px] font-medium"
                            title={t.storedRank ? 'Level set by admin' : 'Level detected from the name'}>
                            Level {t.rank || 1}
                          </span>
                        </p>
                        {t.tagline && <p className="text-xs text-gray-600 truncate max-w-xs" title={t.tagline}>{t.tagline}</p>}
                        <p className="text-xs text-gray-400">{t.isAcceptShareRide ? 'Shared ✓' : 'Private'}</p>
                        {t.requirementsText && (
                          <p className="text-xs text-amber-700 flex items-center gap-1 mt-0.5" title="Vehicle rules for this type">
                            <ShieldCheck className="w-3 h-3 flex-shrink-0" /> {t.requirementsText}
                          </p>
                        )}
                      </div>
                    </div>
                  </td>
                  <td className="px-4 py-3 text-gray-700">{t.capacity}</td>
                  <td className="px-4 py-3 font-medium text-gray-800">₹{t.baseFare}</td>
                  <td className="px-4 py-3 text-gray-700">₹{t.perKm}</td>
                  <td className="px-4 py-3 text-gray-700">₹{t.minFare}</td>
                  <td className="px-4 py-3 text-gray-700">{t.baseDistance ?? 2} km</td>
                  {/* Services badges */}
                  <td className="px-4 py-3">
                    <div className="flex flex-wrap gap-1">
                      {(t.services || ['taxi']).map((s: string) => (
                        <span key={s} className="px-2 py-0.5 bg-blue-50 text-blue-700 rounded-full text-xs font-medium capitalize">
                          {ALL_SERVICES.find(x => x.key === s)?.label.split(' ')[0] || s}
                        </span>
                      ))}
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-1">
                      <button type="button" onClick={() => openEdit(t)}
                        className="p-1.5 hover:bg-blue-50 rounded-lg text-blue-600" title="Edit">
                        <Pencil className="w-4 h-4" />
                      </button>
                      <button type="button" onClick={() => handleDelete(t._id)}
                        className="p-1.5 hover:bg-red-50 rounded-lg text-red-500" title="Delete">
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </td>
                </tr>
                )),
              ])}
              {types.length === 0 && (
                <tr>
                  <td colSpan={8} className="text-center text-gray-400 py-12">
                    <Car className="w-8 h-8 mx-auto mb-2 opacity-20" />
                    No vehicle types yet
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Modal */}
      {showModal && (
        <Modal title={editItem ? 'Edit Vehicle Type' : 'Add Vehicle Type'} onClose={() => setShowModal(false)}>
          <form onSubmit={handleSave} className="space-y-5">

            {/* Image upload */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">Vehicle Image</label>
              <div className="flex items-center gap-4">
                <div className="w-28 h-20 rounded-xl border-2 border-dashed border-gray-200 bg-gray-50 flex items-center justify-center overflow-hidden flex-shrink-0">
                  {preview
                    ? <img src={preview} alt="preview" className="w-full h-full object-contain p-1" />
                    : <Car className="w-8 h-8 text-gray-300" />
                  }
                </div>
                <div>
                  <input ref={fileRef} type="file" accept="image/*" className="hidden"
                    title="Upload vehicle image" aria-label="Upload vehicle image"
                    onChange={handleImageUpload} />
                  <button type="button" onClick={() => fileRef.current?.click()} disabled={uploading}
                    className="flex items-center gap-2 px-4 py-2 border border-gray-300 rounded-lg text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-60">
                    <Upload className="w-4 h-4" />
                    {uploading ? 'Uploading...' : 'Upload Image'}
                  </button>
                  <p className="text-xs text-gray-400 mt-1">PNG, JPG, SVG · Recommended 200×120px</p>
                </div>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div className="col-span-2">
                <label htmlFor="vtName" className="block text-sm font-medium text-gray-700 mb-1">Type Name *</label>
                <input id="vtName" required value={form.name}
                  onChange={e => setForm({ ...form, name: e.target.value })}
                  placeholder="e.g. Bike, Auto, Sedan, SUV"
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="vtCap" className="block text-sm font-medium text-gray-700 mb-1">Seats</label>
                <input id="vtCap" type="number" min={1} value={form.capacity}
                  onChange={e => setForm({ ...form, capacity: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="vtBase" className="block text-sm font-medium text-gray-700 mb-1">Base Fare (₹)</label>
                <input id="vtBase" type="number" value={form.baseFare}
                  onChange={e => setForm({ ...form, baseFare: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="vtFreeKm" className="block text-sm font-medium text-gray-700 mb-1">Free KM in Base</label>
                <input id="vtFreeKm" type="number" step="0.5" value={form.baseDistance}
                  onChange={e => setForm({ ...form, baseDistance: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="vtKm" className="block text-sm font-medium text-gray-700 mb-1">Per KM (₹)</label>
                <input id="vtKm" type="number" step="0.5" value={form.perKm}
                  onChange={e => setForm({ ...form, perKm: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="vtMin" className="block text-sm font-medium text-gray-700 mb-1">Per Min (₹)</label>
                <input id="vtMin" type="number" step="0.5" value={form.perMin}
                  onChange={e => setForm({ ...form, perMin: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="vtMinFare" className="block text-sm font-medium text-gray-700 mb-1">Min Fare (₹)</label>
                <input id="vtMinFare" type="number" value={form.minFare}
                  onChange={e => setForm({ ...form, minFare: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="vtWait" className="block text-sm font-medium text-gray-700 mb-1">Waiting (₹/min)</label>
                <input id="vtWait" type="number" step="0.5" value={form.waitingCharge}
                  onChange={e => setForm({ ...form, waitingCharge: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
            </div>

            {/* Category + level (tier) */}
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label htmlFor="vtCategory" className="block text-sm font-medium text-gray-700 mb-1">Category</label>
                <select id="vtCategory" value={form.category}
                  onChange={e => setForm({ ...form, category: e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
                  <option value="">Auto-detect from name ({categoryLabel(autoCategory)})</option>
                  {CATEGORY_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
                  {form.category && !knownCategory && <option value={form.category}>{categoryLabel(form.category)}</option>}
                </select>
              </div>
              <div>
                <label htmlFor="vtRank" className="block text-sm font-medium text-gray-700 mb-1">Level</label>
                <input id="vtRank" type="number" min={1} max={5} step={1} value={form.rank}
                  onChange={e => setForm({ ...form, rank: e.target.value })}
                  placeholder={`Auto (${autoRank})`}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <p className="col-span-2 text-xs text-gray-400 -mt-1">
                Level: 1 = basic · higher = premium (Prime Sedan 2, Prime SUV 3). A higher-level driver of the same category can opt in to lower-level rides.
              </p>
              <div className="col-span-2">
                <label htmlFor="vtTagline" className="block text-sm font-medium text-gray-700 mb-1">Tagline <span className="font-normal text-gray-400">(shown to riders)</span></label>
                <input id="vtTagline" maxLength={80} value={form.tagline}
                  onChange={e => setForm({ ...form, tagline: e.target.value })}
                  placeholder="e.g. Top-rated drivers, newer cars"
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                <p className="text-xs text-gray-400 mt-1 text-right">{String(form.tagline || '').length}/80</p>
              </div>
            </div>

            {/* Vehicle rules */}
            <div className="rounded-lg border border-gray-200 p-3 space-y-3">
              <div>
                <p className="text-sm font-medium text-gray-700 flex items-center gap-1.5"><ShieldCheck className="w-4 h-4" /> Requirements</p>
                <p className="text-xs text-gray-400">Checked when a driver registers this vehicle type. Leave empty for no rule.</p>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label htmlFor="vtReqYear" className="block text-xs font-medium text-gray-600 mb-1">Minimum model year</label>
                  <input id="vtReqYear" type="number" min={1990} max={THIS_YEAR + 1} step={1} value={form.reqYear}
                    onChange={e => setForm({ ...form, reqYear: e.target.value })}
                    placeholder="e.g. 2019"
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                </div>
                <div>
                  <label htmlFor="vtReqRating" className="block text-xs font-medium text-gray-600 mb-1">Minimum driver rating</label>
                  <input id="vtReqRating" type="number" min={0.1} max={5} step={0.1} value={form.reqRating}
                    onChange={e => setForm({ ...form, reqRating: e.target.value })}
                    placeholder="e.g. 4.5"
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                </div>
                <div className="col-span-2">
                  <label htmlFor="vtReqModels" className="block text-xs font-medium text-gray-600 mb-1">Allowed models <span className="font-normal text-gray-400">(comma separated)</span></label>
                  <input id="vtReqModels" value={form.reqModels}
                    onChange={e => setForm({ ...form, reqModels: e.target.value })}
                    placeholder="e.g. Dzire, Aura, Ciaz"
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                  <p className="text-xs text-gray-400 mt-1">Empty = any model. A driver&apos;s model matches if it contains one of these names.</p>
                </div>
                <div className="col-span-2">
                  <label htmlFor="vtReqNote" className="block text-xs font-medium text-gray-600 mb-1">Note</label>
                  <input id="vtReqNote" maxLength={200} value={form.reqNote}
                    onChange={e => setForm({ ...form, reqNote: e.target.value })}
                    placeholder="e.g. AC working, clean interior"
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                </div>
              </div>
              <p className="text-xs text-gray-400">The driver rating rule only applies to drivers who already have ratings.</p>
            </div>

            {/* Services */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">Available For Services *</label>
              <div className="grid grid-cols-1 gap-2">
                {ALL_SERVICES.map(s => (
                  <label key={s.key} className={`flex items-center gap-3 p-3 rounded-lg border cursor-pointer transition-colors ${
                    form.services.includes(s.key)
                      ? 'border-blue-300 bg-blue-50'
                      : 'border-gray-200 hover:bg-gray-50'
                  }`}>
                    <input type="checkbox" checked={form.services.includes(s.key)}
                      onChange={() => toggleService(s.key)}
                      className="w-4 h-4 rounded text-blue-600 border-gray-300" />
                    <span className="text-sm font-medium text-gray-800">{s.label}</span>
                  </label>
                ))}
              </div>
            </div>

            <div className="flex items-center gap-3">
              <input id="vtShare" type="checkbox" checked={form.isAcceptShareRide}
                onChange={e => setForm({ ...form, isAcceptShareRide: e.target.checked })}
                className="w-4 h-4 rounded text-blue-600 border-gray-300" />
              <label htmlFor="vtShare" className="text-sm font-medium text-gray-700 cursor-pointer">Accept Shared / Pool Rides</label>
            </div>

            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setShowModal(false)}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">Cancel</button>
              <button type="submit" disabled={uploading}
                className="flex-1 bg-primary text-white rounded-lg py-2 text-sm font-medium hover:bg-primary-dark disabled:opacity-60">
                {editItem ? 'Save Changes' : 'Add Vehicle Type'}
              </button>
            </div>
          </form>
        </Modal>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}

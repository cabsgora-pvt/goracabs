'use client'
import { useEffect, useState } from 'react'
import { Header } from '@/components/header'
import { Toast } from '@/components/ui/toast'
import { zoneFetch, useZoneSession } from '@/components/zone-shell'

// Fares the zone admin sets for their own zones. Only the fare fields that
// apply to each service are shown; commission and GST are Gora's.
const FIELDS_BY_SERVICE: Record<string, { key: string; label: string }[]> = {
  taxi: [
    { key: 'baseFare', label: 'Base fare ₹' }, { key: 'perKm', label: 'Per km ₹' },
    { key: 'perMin', label: 'Per min ₹' }, { key: 'minFare', label: 'Min fare ₹' },
  ],
  delivery: [
    { key: 'baseFare', label: 'Base fare ₹' }, { key: 'perKm', label: 'Per km ₹' },
    { key: 'perMin', label: 'Per min ₹' }, { key: 'minFare', label: 'Min fare ₹' }, { key: 'perKg', label: 'Per kg ₹' },
  ],
  outstation: [
    { key: 'baseFare', label: 'Base fare ₹' }, { key: 'perKm', label: 'Per km ₹' }, { key: 'minFare', label: 'Min fare ₹' },
    { key: 'driverAllowance', label: 'Driver allowance ₹/day' }, { key: 'nightHaltCharge', label: 'Night halt ₹' },
    { key: 'emptyReturnPercent', label: 'Empty return %' }, { key: 'rtBaseFare', label: 'Round trip base ₹' },
    { key: 'rtPerKm', label: 'Round trip per km ₹' }, { key: 'kmLimitPerDay', label: 'Km limit / day' },
    { key: 'extraKmRate', label: 'Extra km ₹' },
  ],
  hire_driver: [
    { key: 'baseFare', label: 'Base fare ₹' }, { key: 'perHour', label: 'Per hour ₹' },
    { key: 'hireReturnCharge', label: 'One-way return ₹' }, { key: 'minFare', label: 'Min fare ₹' },
  ],
}
const RENTAL_FIELDS = [
  { key: 'hours', label: 'Hours' }, { key: 'km', label: 'Km' }, { key: 'basePrice', label: 'Package price ₹' },
  { key: 'extraHourRate', label: 'Extra hour ₹' }, { key: 'extraKmRate', label: 'Extra km ₹' }, { key: 'nightCharge', label: 'Night charge ₹' },
]
const SERVICE_LABEL: Record<string, string> = { taxi: 'Taxi', delivery: 'Parcel', outstation: 'Outstation', hire_driver: 'Hire a driver', rental: 'Rental' }

export default function ZonePricing() {
  const session = useZoneSession()
  const readOnly = !!session?.readOnly
  const [limitPct, setLimitPct] = useState<number | null>(null)
  const [zones, setZones] = useState<any[] | null>(null)
  const [edits, setEdits] = useState<Record<string, Record<string, string>>>({})
  const [saving, setSaving] = useState<string | null>(null)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  useEffect(() => { zoneFetch('/api/zone-admin/pricing').then(r => r.json()).then(d => { setZones(d.zones || []); setLimitPct(d.limitPct ?? null) }).catch(() => {}) }, [])

  const val = (rowId: string, key: string, original: any) => edits[rowId]?.[key] ?? String(original ?? 0)
  const setVal = (rowId: string, key: string, v: string) => setEdits(e => ({ ...e, [rowId]: { ...(e[rowId] || {}), [key]: v } }))

  const save = async (zoneId: string, kind: 'pricing' | 'rental', rowId: string) => {
    const values = edits[rowId]
    if (!values || !Object.keys(values).length) return
    setSaving(rowId)
    try {
      const res = await zoneFetch('/api/zone-admin/pricing', {
        method: 'PUT', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ zoneId, kind, rowId, values: Object.fromEntries(Object.entries(values).map(([k, v]) => [k, Number(v)])) }),
      })
      const d = await res.json()
      if (!res.ok) { setToast({ msg: d.error || 'Could not save', type: 'error' }); return }
      setZones(zs => (zs || []).map(z => String(z._id) === String(zoneId) ? d.zone : z))
      setEdits(e => { const n = { ...e }; delete n[rowId]; return n })
      setToast({ msg: 'Fare saved — new bookings use it now', type: 'success' })
    } finally { setSaving(null) }
  }

  const field = 'w-full border border-[#ced4da] rounded px-2 py-1.5 text-[13px] focus:outline-none focus:border-[#a0a8c4]'

  return (
    <div>
      <Header title="Zone Pricing" />
      <div className="p-6 space-y-6">
        {limitPct ? <p className="text-[13px] text-gray-600">You can move each fare up to ±{limitPct}% from the fare Gora set. For a bigger change, ask Gora.</p> : null}
        {readOnly && <p className="text-[13px] text-red-600">Read-only until your subscription is renewed.</p>}
        {!zones ? <p className="text-gray-400">Loading…</p> : zones.length === 0 ? <p className="text-gray-500">No zones assigned to you yet.</p> :
          zones.map(z => (
            <div key={z._id} className="space-y-4">
              <h4 className="text-[16px] font-semibold text-[#495057]">{z.name}{z.city ? ` · ${z.city}` : ''}</h4>
              {(z.pricing || []).length === 0 && (z.rentalPackages || []).length === 0 && (
                <p className="text-[13px] text-gray-500">No fares set up in this zone yet. Ask Gora to add the vehicles and services.</p>
              )}
              {(z.pricing || []).map((row: any) => {
                const fields = FIELDS_BY_SERVICE[row.service] || FIELDS_BY_SERVICE.taxi
                const dirty = !!edits[row._id] && Object.keys(edits[row._id]).length > 0
                return (
                  <div key={row._id} className="bg-white rounded shadow-sm p-4">
                    <div className="flex items-center justify-between mb-3">
                      <p className="font-semibold text-[14px] text-[#495057]">
                        {row.vehicleTypeName} · <span className="text-primary">{SERVICE_LABEL[row.service] || row.service}</span>
                        {row.isActive === false && <span className="ml-2 text-[11px] text-gray-400">(off)</span>}
                      </p>
                      <button type="button" disabled={readOnly || !dirty || saving === row._id} onClick={() => save(z._id, 'pricing', row._id)}
                        className="px-3 py-1.5 rounded bg-primary text-white text-[12.5px] disabled:opacity-40">
                        {saving === row._id ? 'Saving…' : 'Save'}
                      </button>
                    </div>
                    <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
                      {fields.map(f => (
                        <label key={f.key} className="text-[12px] text-[#878a99]">{f.label}
                          <input type="number" min={0} step="0.01" className={field} value={val(row._id, f.key, row[f.key])}
                            onChange={e => setVal(row._id, f.key, e.target.value)} />
                        </label>
                      ))}
                    </div>
                  </div>
                )
              })}
              {(z.rentalPackages || []).map((pkg: any) => {
                const dirty = !!edits[pkg._id] && Object.keys(edits[pkg._id]).length > 0
                return (
                  <div key={pkg._id} className="bg-white rounded shadow-sm p-4">
                    <div className="flex items-center justify-between mb-3">
                      <p className="font-semibold text-[14px] text-[#495057]">{pkg.vehicleTypeName} · <span className="text-primary">Rental {pkg.hours} hr / {pkg.km} km</span></p>
                      <button type="button" disabled={readOnly || !dirty || saving === pkg._id} onClick={() => save(z._id, 'rental', pkg._id)}
                        className="px-3 py-1.5 rounded bg-primary text-white text-[12.5px] disabled:opacity-40">
                        {saving === pkg._id ? 'Saving…' : 'Save'}
                      </button>
                    </div>
                    <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
                      {RENTAL_FIELDS.map(f => (
                        <label key={f.key} className="text-[12px] text-[#878a99]">{f.label}
                          <input type="number" min={0} step="0.01" className={field} value={val(pkg._id, f.key, pkg[f.key])}
                            onChange={e => setVal(pkg._id, f.key, e.target.value)} />
                        </label>
                      ))}
                    </div>
                  </div>
                )
              })}
            </div>
          ))}
        <p className="text-xs text-gray-500">Commission and GST are set by Gora. A new fare applies to bookings quoted after you save.</p>
      </div>
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}

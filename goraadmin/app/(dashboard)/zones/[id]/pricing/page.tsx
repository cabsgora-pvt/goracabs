'use client'
import { useState, useEffect, useCallback } from 'react'
import { useParams } from 'next/navigation'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { ArrowLeft, Pencil, Car, ToggleLeft, ToggleRight, Plus, Trash2, Clock } from 'lucide-react'
import Link from 'next/link'

const TABS = [
  { key: 'taxi',        label: 'Taxi' },
  { key: 'rental',      label: 'Rental' },
  { key: 'outstation',  label: 'Outstation' },
  { key: 'delivery',    label: 'Delivery' },
  { key: 'hire_driver', label: 'Hire a Driver' },
]

type VehicleType = { _id: string; name: string; imageUrl: string; services: string[]; baseFare: number; perKm: number; perMin: number; minFare: number }
type PricingRow  = { vehicleTypeId: string; vehicleTypeName: string; service: string; baseFare: number; perKm: number; perMin: number; minFare: number; commissionPercent: number; isActive: boolean; nightHaltCharge?: number; emptyReturnPercent?: number; perHour?: number; perKg?: number; outPerHour?: number; rtBaseFare?: number; rtPerKm?: number; rtPerHour?: number; hireReturnCharge?: number }
type RentalPackage = { vehicleTypeId: string; vehicleTypeName: string; hours: number; km: number; basePrice: number; extraHourRate: number; extraKmRate: number; nightCharge: number; commissionPercent: number; isActive: boolean }
// extra outstation fields tacked onto PricingRow: outPerHour, rtBaseFare, rtPerKm, rtPerHour

export default function ZonePricingPage() {
  const { id } = useParams()
  const [zoneName, setZoneName]   = useState('')
  const [vehicles, setVehicles]   = useState<VehicleType[]>([])
  const [pricing, setPricing]     = useState<PricingRow[]>([])
  const [loading, setLoading]     = useState(true)
  const [saving, setSaving]       = useState(false)
  const [activeTab, setActiveTab] = useState('taxi')
  const [editRow, setEditRow]     = useState<PricingRow | null>(null)
  const [editForm, setEditForm]   = useState<PricingRow | null>(null)
  const [rentalPackages, setRentalPackages] = useState<RentalPackage[]>([])
  const [savingRental, setSavingRental]     = useState(false)
  const [toast, setToast]         = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const fetchData = useCallback(async () => {
    try {
      const [zoneRes, pricingRes, vehicleRes, rentalRes] = await Promise.all([
        fetch(`/api/zones/${id}`).then(r => r.json()),
        fetch(`/api/zones/${id}/pricing`).then(r => r.json()),
        fetch('/api/vehicles/types').then(r => r.json()),
        fetch(`/api/zones/${id}/rental-packages`).then(r => r.json()),
      ])
      setZoneName(zoneRes.name || '')
      setRentalPackages((rentalRes.packages || []).map((p: any) => ({
        vehicleTypeId: p.vehicleTypeId, vehicleTypeName: p.vehicleTypeName,
        hours: p.hours, km: p.km, basePrice: p.basePrice,
        extraHourRate: p.extraHourRate, extraKmRate: p.extraKmRate,
        nightCharge: p.nightCharge ?? 0, commissionPercent: p.commissionPercent ?? 20,
        isActive: p.isActive !== false,
      })))
      const allVehicles: VehicleType[] = vehicleRes.types || []
      setVehicles(allVehicles)

      // Build full pricing matrix — all vehicles × all services
      const existingPricing: PricingRow[] = pricingRes.pricing || []
      const fullMatrix: PricingRow[] = []

      TABS.forEach(({ key: service }) => {
        allVehicles.forEach(v => {
          const existing = existingPricing.find(
            p => p.vehicleTypeId === v._id && p.service === service
          )
          fullMatrix.push(existing || {
            vehicleTypeId: v._id,
            vehicleTypeName: v.name,
            service,
            baseFare: v.baseFare,
            perKm: v.perKm,
            perMin: v.perMin,
            minFare: v.minFare,
            commissionPercent: 20,
            isActive: false,
            nightHaltCharge: 0,
            emptyReturnPercent: 0,
            perHour: 0,
            perKg: 0,
            outPerHour: 0,
            rtBaseFare: 0,
            rtPerKm: 0,
            rtPerHour: 0,
            hireReturnCharge: 0,
          })
        })
      })
      setPricing(fullMatrix)
    } catch { /* keep empty */ }
    setLoading(false)
  }, [id])

  useEffect(() => { fetchData() }, [fetchData])

  // Vehicles for active tab that support this service
  const tabVehicles = vehicles.filter(v => (v.services || []).includes(activeTab))
  const tabPricing  = pricing.filter(p => p.service === activeTab)

  // Get pricing row for a vehicle in current tab
  const getPricingRow = (vehicleId: string) =>
    tabPricing.find(p => p.vehicleTypeId === vehicleId)

  // Toggle vehicle on/off for this service
  const toggleVehicle = (vehicleId: string) => {
    setPricing(prev => prev.map(p =>
      p.vehicleTypeId === vehicleId && p.service === activeTab
        ? { ...p, isActive: !p.isActive }
        : p
    ))
  }

  // Open edit modal
  const openEdit = (row: PricingRow) => { setEditRow(row); setEditForm({ ...row }) }

  // Save edited row locally
  const saveEdit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!editForm) return
    setPricing(prev => prev.map(p =>
      p.vehicleTypeId === editRow?.vehicleTypeId && p.service === editRow?.service ? editForm : p
    ))
    setEditRow(null)
    setToast({ msg: 'Pricing updated — click Save All to persist', type: 'success' })
  }

  // Save all to DB
  const saveAll = async () => {
    setSaving(true)
    const res = await fetch(`/api/zones/${id}/pricing`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pricing: pricing.filter(p => p.isActive) }),
    })
    setSaving(false)
    if (res.ok) setToast({ msg: 'All pricing saved!', type: 'success' })
    else setToast({ msg: 'Failed to save', type: 'error' })
  }

  // ── Rental packages management ──
  const addPackage = (v: VehicleType) => {
    setRentalPackages(prev => [...prev, {
      vehicleTypeId: v._id, vehicleTypeName: v.name,
      hours: 4, km: 40, basePrice: 0, extraHourRate: 0, extraKmRate: 0,
      nightCharge: 0, commissionPercent: 20, isActive: true,
    }])
  }
  const updatePackage = (idx: number, patch: Partial<RentalPackage>) => {
    setRentalPackages(prev => prev.map((p, i) => i === idx ? { ...p, ...patch } : p))
  }
  const removePackage = (idx: number) => {
    setRentalPackages(prev => prev.filter((_, i) => i !== idx))
  }
  const saveRentalPackages = async () => {
    setSavingRental(true)
    const res = await fetch(`/api/zones/${id}/rental-packages`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ packages: rentalPackages }),
    })
    setSavingRental(false)
    setToast(res.ok ? { msg: 'Rental packages saved!', type: 'success' } : { msg: 'Failed to save packages', type: 'error' })
  }

  if (loading) return (
    <div><Header title="Zone Pricing" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  return (
    <div>
      <Header title="Zone Pricing" />
      <div className="p-6 space-y-6">

        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Link href="/zones" className="p-2 hover:bg-gray-100 rounded-lg text-gray-600">
              <ArrowLeft className="w-5 h-5" />
            </Link>
            <PageHeader
              title={zoneName ? `${zoneName} — Pricing` : 'Zone Pricing'}
              subtitle="Enable vehicles per service and set their prices"
            />
          </div>
          <button type="button" onClick={saveAll} disabled={saving}
            className="px-6 py-2.5 bg-primary text-white rounded-lg text-sm font-semibold hover:bg-primary-dark disabled:opacity-60">
            {saving ? 'Saving...' : 'Save All'}
          </button>
        </div>

        {/* Service tabs */}
        <div className="flex gap-1 bg-gray-100 p-1 rounded-xl w-fit flex-wrap">
          {TABS.map(t => (
            <button key={t.key} type="button" onClick={() => setActiveTab(t.key)}
              className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                activeTab === t.key ? 'bg-white text-gray-800 shadow-sm' : 'text-gray-500 hover:text-gray-700'
              }`}>
              {t.label}
            </button>
          ))}
        </div>

        {/* ── RENTAL: package builder UI ── */}
        {activeTab === 'rental' ? (
          <div className="space-y-5">
            <div className="flex items-center justify-between">
              <p className="text-sm text-gray-500">Create hourly rental packages (e.g. 4hr/40km, 8hr/80km) per vehicle.</p>
              <button type="button" onClick={saveRentalPackages} disabled={savingRental}
                className="px-5 py-2 bg-primary text-white rounded-lg text-sm font-semibold hover:bg-primary-dark disabled:opacity-60">
                {savingRental ? 'Saving...' : 'Save Packages'}
              </button>
            </div>

            {tabVehicles.length === 0 ? (
              <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-12 text-center">
                <Car className="w-10 h-10 mx-auto mb-3 text-gray-200" />
                <p className="text-gray-500 font-medium">No vehicles support Rental</p>
                <p className="text-gray-400 text-sm mt-1">Go to <Link href="/vehicles/types" className="text-blue-600 underline">Vehicle Types</Link> and enable Rental for a vehicle</p>
              </div>
            ) : tabVehicles.map(v => {
              const pkgs = rentalPackages.map((p, i) => ({ p, i })).filter(({ p }) => p.vehicleTypeId === v._id)
              return (
                <div key={v._id} className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden">
                  <div className="flex items-center justify-between px-4 py-3 bg-gray-50 border-b border-gray-100">
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-8 rounded bg-white border border-gray-100 flex items-center justify-center overflow-hidden">
                        {v.imageUrl ? <img src={v.imageUrl} alt={v.name} className="w-full h-full object-contain p-0.5" /> : <Car className="w-4 h-4 text-gray-300" />}
                      </div>
                      <span className="font-semibold text-gray-900">{v.name}</span>
                      <span className="text-xs text-gray-400">{pkgs.length} package{pkgs.length !== 1 ? 's' : ''}</span>
                    </div>
                    <button type="button" onClick={() => addPackage(v)}
                      className="flex items-center gap-1 px-3 py-1.5 bg-primary/10 text-primary rounded-lg text-xs font-semibold hover:bg-primary/20">
                      <Plus className="w-3.5 h-3.5" /> Add Package
                    </button>
                  </div>

                  {pkgs.length === 0 ? (
                    <div className="px-4 py-6 text-center text-sm text-gray-400">No packages yet — click "Add Package"</div>
                  ) : (
                    <div className="divide-y divide-gray-50">
                      {pkgs.map(({ p, i }) => (
                        <div key={i} className="px-4 py-3 grid grid-cols-2 md:grid-cols-7 gap-3 items-end">
                          <NumField label="Hours" value={p.hours} onChange={n => updatePackage(i, { hours: n })} />
                          <NumField label="Incl. KM" value={p.km} onChange={n => updatePackage(i, { km: n })} />
                          <NumField label="Base ₹" value={p.basePrice} onChange={n => updatePackage(i, { basePrice: n })} />
                          <NumField label="Extra Hr ₹" value={p.extraHourRate} onChange={n => updatePackage(i, { extraHourRate: n })} />
                          <NumField label="Extra KM ₹" value={p.extraKmRate} onChange={n => updatePackage(i, { extraKmRate: n })} />
                          <NumField label="Commission %" value={p.commissionPercent} onChange={n => updatePackage(i, { commissionPercent: n })} />
                          <div className="flex items-center gap-2">
                            <button type="button" onClick={() => updatePackage(i, { isActive: !p.isActive })}
                              title={p.isActive ? 'Active' : 'Inactive'} className="text-gray-400">
                              {p.isActive ? <ToggleRight className="w-7 h-7 text-green-500" /> : <ToggleLeft className="w-7 h-7 text-gray-300" />}
                            </button>
                            <button type="button" onClick={() => removePackage(i)} title="Delete"
                              className="p-1.5 hover:bg-red-50 rounded-lg text-red-500"><Trash2 className="w-4 h-4" /></button>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        ) : tabVehicles.length === 0 ? (
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-12 text-center">
            <Car className="w-10 h-10 mx-auto mb-3 text-gray-200" />
            <p className="text-gray-500 font-medium">No vehicles support this service</p>
            <p className="text-gray-400 text-sm mt-1">
              Go to <Link href="/vehicles/types" className="text-blue-600 underline">Vehicle Types</Link> and enable this service for a vehicle
            </p>
          </div>
        ) : (
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b border-gray-100">
                  <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Vehicle</th>
                  <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Active</th>
                  <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Base Fare</th>
                  <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Per KM</th>
                  <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Per Min</th>
                  <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Min Fare</th>
                  <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Commission</th>
                  <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">Edit</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {tabVehicles.map(v => {
                  const row = getPricingRow(v._id)
                  const active = row?.isActive ?? false
                  return (
                    <tr key={v._id} className={`transition-colors ${active ? 'hover:bg-gray-50' : 'opacity-50 bg-gray-50/50'}`}>
                      {/* Vehicle image + name */}
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-3">
                          <div className="w-12 h-9 rounded-lg bg-gray-50 border border-gray-100 flex items-center justify-center overflow-hidden flex-shrink-0">
                            {v.imageUrl
                              ? <img src={v.imageUrl} alt={v.name} className="w-full h-full object-contain p-0.5" />
                              : <Car className="w-5 h-5 text-gray-300" />
                            }
                          </div>
                          <span className="font-semibold text-gray-900">{v.name}</span>
                        </div>
                      </td>
                      {/* Toggle */}
                      <td className="px-4 py-3">
                        <button type="button" onClick={() => toggleVehicle(v._id)}
                          title={active ? 'Disable for this service' : 'Enable for this service'}
                          className="text-gray-400 hover:text-primary transition-colors">
                          {active
                            ? <ToggleRight className="w-8 h-8 text-green-500" />
                            : <ToggleLeft  className="w-8 h-8 text-gray-300" />
                          }
                        </button>
                      </td>
                      {/* Pricing */}
                      <td className="px-4 py-3 font-medium text-gray-800">₹{row?.baseFare ?? v.baseFare}</td>
                      <td className="px-4 py-3 text-gray-700">₹{row?.perKm ?? v.perKm}</td>
                      <td className="px-4 py-3 text-gray-700">₹{row?.perMin ?? v.perMin}</td>
                      <td className="px-4 py-3 text-gray-700">₹{row?.minFare ?? v.minFare}</td>
                      <td className="px-4 py-3">
                        <span className="px-2 py-1 bg-green-50 text-green-700 rounded-md text-xs font-semibold">{row?.commissionPercent ?? 20}%</span>
                      </td>
                      {/* Edit */}
                      <td className="px-4 py-3">
                        <button type="button" title="Edit pricing" disabled={!active}
                          onClick={() => row && openEdit(row)}
                          className="p-1.5 hover:bg-blue-50 rounded-lg text-blue-600 disabled:opacity-30 disabled:cursor-not-allowed">
                          <Pencil className="w-4 h-4" />
                        </button>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}

        {/* Helper text */}
        <p className="text-xs text-gray-400">
          Toggle vehicles ON to enable them for this service in this zone. Edit prices, then click <strong>Save All</strong>.
        </p>
      </div>

      {/* Edit modal */}
      {editRow && editForm && (
        <Modal title={`${editRow.vehicleTypeName} — ${TABS.find(t => t.key === editRow.service)?.label}`} onClose={() => setEditRow(null)}>
          <form onSubmit={saveEdit} className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              {[
                { id: 'p-base', label: 'Base Fare (₹)', key: 'baseFare' },
                { id: 'p-km',   label: 'Per KM (₹)',    key: 'perKm' },
                { id: 'p-min',  label: 'Per Min (₹)',   key: 'perMin' },
                { id: 'p-mf',   label: 'Min Fare (₹)',  key: 'minFare' },
              ].map(f => (
                <div key={f.key}>
                  <label htmlFor={f.id} className="block text-sm font-medium text-gray-700 mb-1">{f.label}</label>
                  <input id={f.id} type="number" step="0.5"
                    value={editForm[f.key as keyof PricingRow] as number}
                    onChange={e => setEditForm({ ...editForm, [f.key]: +e.target.value })}
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                </div>
              ))}
            </div>
            {/* Commission — admin profit % */}
            <div className="bg-green-50 border border-green-200 rounded-lg p-3">
              <label htmlFor="p-commission" className="block text-sm font-medium text-green-800 mb-1">
                Admin Commission (%) — your profit per ride
              </label>
              <input id="p-commission" type="number" step="1" min="0" max="100"
                value={editForm.commissionPercent}
                onChange={e => setEditForm({ ...editForm, commissionPercent: +e.target.value })}
                className="w-full border border-green-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-green-500" />
              <p className="text-xs text-green-600 mt-1">
                e.g. 20% on ₹100 fare → admin keeps ₹20, driver gets ₹80
              </p>
            </div>
            {/* Hire-a-driver: per-hour rate (the customer's car, priced by hours) */}
            {editRow.service === 'hire_driver' && (
              <div className="bg-indigo-50 border border-indigo-200 rounded-lg p-3">
                <label htmlFor="p-perhour" className="block text-sm font-medium text-indigo-800 mb-1">Per Hour Rate (₹) — driver pay per hour</label>
                <input id="p-perhour" type="number" step="10" min="0"
                  value={editForm.perHour || 0}
                  onChange={e => setEditForm({ ...editForm, perHour: +e.target.value })}
                  className="w-full border border-indigo-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                <p className="text-xs text-indigo-700 mt-1">Fare = Base + (total hours × this rate). e.g. ₹150/hr × 4 hr = ₹600 + base.</p>
                <div className="mt-3">
                  <label htmlFor="p-hireret" className="block text-sm font-medium text-indigo-800 mb-1">One-Way Return Charge (₹) — driver's return</label>
                  <input id="p-hireret" type="number" step="10" min="0"
                    value={editForm.hireReturnCharge || 0}
                    onChange={e => setEditForm({ ...editForm, hireReturnCharge: +e.target.value })}
                    className="w-full border border-indigo-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500" />
                  <p className="text-xs text-indigo-700 mt-1">Added only for One-Way trips (driver returns alone). Round-trip = ₹0.</p>
                </div>
              </div>
            )}
            {/* Delivery: per-kg weight charge (base + km already above) */}
            {editRow.service === 'delivery' && (
              <div className="bg-teal-50 border border-teal-200 rounded-lg p-3">
                <label htmlFor="p-perkg" className="block text-sm font-medium text-teal-800 mb-1">Per KG Rate (₹) — parcel weight charge</label>
                <input id="p-perkg" type="number" step="5" min="0"
                  value={editForm.perKg || 0}
                  onChange={e => setEditForm({ ...editForm, perKg: +e.target.value })}
                  className="w-full border border-teal-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-teal-500" />
                <p className="text-xs text-teal-700 mt-1">Fare = Base + (km × Per KM) + (weight × this). e.g. ₹40 base + 5km×₹6 + 3kg×₹10 = ₹100.</p>
              </div>
            )}
            {/* Outstation-only extras: only shown when editing an outstation pricing row */}
            {editRow.service === 'outstation' && (
              <div className="bg-orange-50 border border-orange-200 rounded-lg p-3 space-y-3">
                <p className="text-sm font-semibold text-orange-800">Outstation Pricing</p>
                <p className="text-xs text-orange-600">Base Fare + Per KM above are the <b>One-Way</b> rates. Set the hour charge + Round-Trip rates here.</p>
                <div>
                  <label htmlFor="p-owhr" className="block text-xs font-medium text-orange-800 mb-1">One-Way · Per Hour (₹) — time charge</label>
                  <input id="p-owhr" type="number" step="5" min="0"
                    value={editForm.outPerHour || 0}
                    onChange={e => setEditForm({ ...editForm, outPerHour: +e.target.value })}
                    className="w-full border border-orange-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500" />
                </div>
                <div className="grid grid-cols-3 gap-2 pt-1 border-t border-orange-200">
                  <div>
                    <label htmlFor="p-rtbase" className="block text-[10px] font-medium text-orange-800 mb-1">Round-Trip Base ₹</label>
                    <input id="p-rtbase" type="number" step="10" min="0" value={editForm.rtBaseFare || 0}
                      onChange={e => setEditForm({ ...editForm, rtBaseFare: +e.target.value })}
                      className="w-full border border-orange-300 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500" />
                  </div>
                  <div>
                    <label htmlFor="p-rtkm" className="block text-[10px] font-medium text-orange-800 mb-1">RT Per KM ₹</label>
                    <input id="p-rtkm" type="number" step="1" min="0" value={editForm.rtPerKm || 0}
                      onChange={e => setEditForm({ ...editForm, rtPerKm: +e.target.value })}
                      className="w-full border border-orange-300 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500" />
                  </div>
                  <div>
                    <label htmlFor="p-rthr" className="block text-[10px] font-medium text-orange-800 mb-1">RT Per Hr ₹</label>
                    <input id="p-rthr" type="number" step="5" min="0" value={editForm.rtPerHour || 0}
                      onChange={e => setEditForm({ ...editForm, rtPerHour: +e.target.value })}
                      className="w-full border border-orange-300 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500" />
                  </div>
                </div>
                <p className="text-[11px] text-orange-600">Round-Trip rates blank/0 → falls back to One-Way rates × distance(×2).</p>
                <div>
                  <label htmlFor="p-night" className="block text-xs font-medium text-orange-800 mb-1">Night Halt (₹ per night) — round trip only</label>
                  <input id="p-night" type="number" step="50" min="0"
                    value={editForm.nightHaltCharge || 0}
                    onChange={e => setEditForm({ ...editForm, nightHaltCharge: +e.target.value })}
                    className="w-full border border-orange-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500" />
                  <p className="text-xs text-orange-700 mt-1">Charged when round-trip is overnight. e.g. ₹400/night for driver lodging.</p>
                </div>
                <div>
                  <label htmlFor="p-empty" className="block text-xs font-medium text-orange-800 mb-1">Empty Return (% of fare) — one way only</label>
                  <input id="p-empty" type="number" step="5" min="0" max="100"
                    value={editForm.emptyReturnPercent || 0}
                    onChange={e => setEditForm({ ...editForm, emptyReturnPercent: +e.target.value })}
                    className="w-full border border-orange-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500" />
                  <p className="text-xs text-orange-700 mt-1">Added back when driver returns empty. e.g. 30% means ₹100 fare → ₹130 total.</p>
                </div>
              </div>
            )}
            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setEditRow(null)}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">Cancel</button>
              <button type="submit"
                className="flex-1 bg-primary text-white rounded-lg py-2 text-sm font-medium hover:bg-primary-dark">Update</button>
            </div>
          </form>
        </Modal>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}

// Small labelled number input used in the rental package rows
function NumField({ label, value, onChange }: { label: string; value: number; onChange: (n: number) => void }) {
  return (
    <div>
      <label className="block text-[10px] font-medium text-gray-500 uppercase mb-1">{label}</label>
      <input type="number" step="1" min="0" value={value} title={label} placeholder={label}
        onChange={e => onChange(+e.target.value)}
        className="w-full border border-gray-300 rounded-lg px-2.5 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
    </div>
  )
}

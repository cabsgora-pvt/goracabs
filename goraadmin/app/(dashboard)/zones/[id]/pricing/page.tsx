'use client'
import { useState, useEffect, useCallback } from 'react'
import { useParams } from 'next/navigation'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { ArrowLeft, Pencil, Car, ToggleLeft, ToggleRight } from 'lucide-react'
import Link from 'next/link'

const TABS = [
  { key: 'taxi',        label: 'Taxi' },
  { key: 'rental',      label: 'Rental' },
  { key: 'outstation',  label: 'Outstation' },
  { key: 'delivery',    label: 'Delivery' },
  { key: 'hire_driver', label: 'Hire a Driver' },
]

type VehicleType = { _id: string; name: string; imageUrl: string; services: string[]; baseFare: number; perKm: number; perMin: number; minFare: number }
type PricingRow  = { vehicleTypeId: string; vehicleTypeName: string; service: string; baseFare: number; perKm: number; perMin: number; minFare: number; commissionPercent: number; isActive: boolean; nightHaltCharge?: number; emptyReturnPercent?: number }

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
  const [toast, setToast]         = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const fetchData = useCallback(async () => {
    try {
      const [zoneRes, pricingRes, vehicleRes] = await Promise.all([
        fetch(`/api/zones/${id}`).then(r => r.json()),
        fetch(`/api/zones/${id}/pricing`).then(r => r.json()),
        fetch('/api/vehicles/types').then(r => r.json()),
      ])
      setZoneName(zoneRes.name || '')
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

        {/* Vehicle list for this service */}
        {tabVehicles.length === 0 ? (
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
            {/* Outstation-only extras: only shown when editing an outstation pricing row */}
            {editRow.service === 'outstation' && (
              <div className="bg-orange-50 border border-orange-200 rounded-lg p-3 space-y-3">
                <p className="text-sm font-semibold text-orange-800">Outstation Extras</p>
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

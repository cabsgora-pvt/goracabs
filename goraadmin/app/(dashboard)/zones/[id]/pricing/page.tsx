'use client'
import { useState, useEffect } from 'react'
import { useParams } from 'next/navigation'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { ArrowLeft, Pencil } from 'lucide-react'
import Link from 'next/link'

type PricingRow = { _id?: string; vehicleTypeName: string; service: string; baseFare: number; perKm: number; perMin: number; minFare: number }

const tabs = ['taxi', 'rental', 'outstation', 'delivery']
const defaultPricing: PricingRow[] = [
  { vehicleTypeName: 'Auto', service: 'taxi', baseFare: 25, perKm: 12, perMin: 1.5, minFare: 40 },
  { vehicleTypeName: 'Sedan', service: 'taxi', baseFare: 50, perKm: 15, perMin: 2, minFare: 70 },
  { vehicleTypeName: 'SUV', service: 'taxi', baseFare: 80, perKm: 20, perMin: 2.5, minFare: 100 },
  { vehicleTypeName: 'Mini', service: 'taxi', baseFare: 40, perKm: 13, perMin: 1.8, minFare: 60 },
]

export default function ZonePricingPage() {
  const { id } = useParams()
  const [zoneName, setZoneName] = useState('')
  const [pricing, setPricing] = useState<PricingRow[]>([])
  const [loading, setLoading] = useState(true)
  const [activeTab, setActiveTab] = useState('taxi')
  const [editRow, setEditRow] = useState<PricingRow | null>(null)
  const [editForm, setEditForm] = useState<PricingRow | null>(null)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  useEffect(() => {
    Promise.all([
      fetch(`/api/zones/${id}`).then(r => r.json()),
      fetch(`/api/zones/${id}/pricing`).then(r => r.json()),
    ]).then(([zone, pricingData]) => {
      setZoneName(zone.name || '')
      const rows = pricingData.pricing?.length ? pricingData.pricing : defaultPricing
      setPricing(rows)
      setLoading(false)
    }).catch(() => { setPricing(defaultPricing); setLoading(false) })
  }, [id])

  const tabPricing = pricing.filter(p => p.service === activeTab)

  const openEdit = (row: PricingRow) => { setEditRow(row); setEditForm({ ...row }) }

  const saveEdit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!editForm) return
    const updated = pricing.map(r =>
      r.vehicleTypeName === editRow?.vehicleTypeName && r.service === editRow?.service ? editForm : r
    )
    const res = await fetch(`/api/zones/${id}/pricing`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pricing: updated }),
    })
    if (res.ok) {
      setPricing(updated)
      setEditRow(null)
      setToast({ msg: 'Pricing updated', type: 'success' })
    } else {
      setToast({ msg: 'Failed to save pricing', type: 'error' })
    }
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
        <div className="flex items-center gap-3">
          <Link href="/zones" className="p-2 hover:bg-gray-100 rounded-lg text-gray-600">
            <ArrowLeft className="w-5 h-5" />
          </Link>
          <PageHeader
            title={zoneName ? `${zoneName} — Pricing` : 'Zone Pricing'}
            subtitle="Set per-vehicle-type pricing for this zone"
          />
        </div>

        <div className="flex gap-1 bg-gray-100 p-1 rounded-xl w-fit">
          {tabs.map(t => (
            <button key={t} type="button" onClick={() => setActiveTab(t)}
              className={`px-5 py-2 rounded-lg text-sm font-medium transition-colors capitalize ${activeTab === t ? 'bg-white text-gray-800 shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}>
              {t}
            </button>
          ))}
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-100">
                {['Vehicle Type', 'Base Fare (₹)', 'Per KM (₹)', 'Per Min (₹)', 'Min Fare (₹)', 'Edit'].map(h => (
                  <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {tabPricing.map(row => (
                <tr key={`${row.vehicleTypeName}-${row.service}`} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium text-gray-800">{row.vehicleTypeName}</td>
                  <td className="px-4 py-3 text-gray-700">₹{row.baseFare}</td>
                  <td className="px-4 py-3 text-gray-700">₹{row.perKm}</td>
                  <td className="px-4 py-3 text-gray-700">₹{row.perMin}</td>
                  <td className="px-4 py-3 text-gray-700">₹{row.minFare}</td>
                  <td className="px-4 py-3">
                    <button type="button" title="Edit pricing" onClick={() => openEdit(row)}
                      className="p-1.5 hover:bg-blue-50 rounded-lg text-blue-600">
                      <Pencil className="w-4 h-4" />
                    </button>
                  </td>
                </tr>
              ))}
              {tabPricing.length === 0 && (
                <tr><td colSpan={6} className="text-center text-gray-400 py-8">No pricing set for this service</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {editRow && editForm && (
        <Modal title={`Edit ${editRow.vehicleTypeName} — ${editRow.service}`} onClose={() => setEditRow(null)} size="sm">
          <form onSubmit={saveEdit} className="space-y-4">
            {[
              { label: 'Base Fare (₹)', key: 'baseFare' },
              { label: 'Per KM (₹)', key: 'perKm' },
              { label: 'Per Min (₹)', key: 'perMin' },
              { label: 'Min Fare (₹)', key: 'minFare' },
            ].map(f => (
              <div key={f.key}>
                <label htmlFor={`pricing-${f.key}`} className="block text-sm font-medium text-gray-700 mb-1">{f.label}</label>
                <input id={`pricing-${f.key}`} type="number" step="0.5"
                  value={editForm[f.key as keyof PricingRow] as number}
                  onChange={e => setEditForm({ ...editForm, [f.key]: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
            ))}
            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setEditRow(null)}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">Cancel</button>
              <button type="submit"
                className="flex-1 bg-primary text-white rounded-lg py-2 text-sm font-medium hover:bg-primary-dark">Save</button>
            </div>
          </form>
        </Modal>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}

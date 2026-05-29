'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Toast } from '@/components/ui/toast'

const FIELDS = [
  { label: 'Base Fare (₹)', key: 'baseFare' },
  { label: 'Per KM Rate (₹)', key: 'perKm' },
  { label: 'Per Minute Rate (₹)', key: 'perMin' },
  { label: 'Minimum Fare (₹)', key: 'minFare' },
  { label: 'Night Surcharge (%)', key: 'nightSurchargePercent' },
  { label: 'Cancellation Fee (₹)', key: 'cancellationFee' },
  { label: 'Driver Commission (%)', key: 'driverCommissionPercent' },
  { label: 'Base Distance (km)', key: 'baseDistance', hint: 'Free km included in base fare' },
  { label: 'Waiting Charge (₹/min)', key: 'waitingCharge' },
]

export default function TaxiServicePage() {
  const [config, setConfig] = useState<any>({
    baseFare: 50, perKm: 15, perMin: 2, minFare: 70,
    nightSurchargePercent: 15, cancellationFee: 30, driverCommissionPercent: 80,
    baseDistance: 2, waitingCharge: 1, priceType: 'both',
  })
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  useEffect(() => {
    fetch('/api/services/taxi')
      .then(r => r.json())
      .then(d => { if (!d.error) setConfig(d); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    const res = await fetch('/api/services/taxi', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...config, service: 'taxi' }),
    })
    setSaving(false)
    setToast(res.ok
      ? { msg: 'Taxi pricing saved!', type: 'success' }
      : { msg: 'Failed to save', type: 'error' })
  }

  if (loading) return (
    <div><Header title="Taxi Pricing" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  return (
    <div>
      <Header title="Taxi Pricing" />
      <div className="p-6 space-y-6">
        <PageHeader title="Taxi Service Pricing" subtitle="Configure fares for taxi service" />
        <form onSubmit={handleSave}>
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6">
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
              {FIELDS.map(f => (
                <div key={f.key}>
                  <label htmlFor={`taxi-${f.key}`} className="block text-sm font-medium text-gray-700 mb-1">{f.label}</label>
                  <input id={`taxi-${f.key}`} type="number" step="0.5"
                    value={config[f.key] ?? 0}
                    onChange={e => setConfig({ ...config, [f.key]: +e.target.value })}
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                  {(f as any).hint && <p className="text-xs text-gray-400 mt-1">{(f as any).hint}</p>}
                </div>
              ))}
              <div>
                <label htmlFor="taxi-priceType" className="block text-sm font-medium text-gray-700 mb-1">Price Type</label>
                <select id="taxi-priceType"
                  value={config.priceType ?? 'both'}
                  onChange={e => setConfig({ ...config, priceType: e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
                  <option value="both">Both</option>
                  <option value="ride_now">Ride Now Only</option>
                  <option value="ride_later">Ride Later Only</option>
                </select>
              </div>
            </div>
            <div className="mt-6 flex justify-end">
              <button type="submit" disabled={saving}
                className="px-8 py-2.5 bg-primary text-white rounded-lg text-sm font-semibold hover:bg-primary-dark disabled:opacity-60">
                {saving ? 'Saving...' : 'Save Pricing'}
              </button>
            </div>
          </div>
        </form>
      </div>
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}

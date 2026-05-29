'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Toast } from '@/components/ui/toast'

export default function HireDriverServicePage() {
  const [config, setConfig] = useState<any>({
    isActive: true, baseFare: 500, perKm: 12, perMin: 2, minFare: 300,
    baseDistance: 0, waitingCharge: 2, driverCommissionPercent: 20,
    cancellationFee: 50, priceType: 'both',
    minHours: 4, perHourRate: 150,
  })
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  useEffect(() => {
    fetch('/api/services/hire_driver')
      .then(r => r.json())
      .then(d => { if (d._id) setConfig(d); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  const save = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    await fetch('/api/services/hire_driver', {
      method: 'PUT', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ service: 'hire_driver', ...config }),
    })
    setSaving(false)
    setToast({ msg: 'Hire a Driver settings saved!', type: 'success' })
  }

  const n = (field: string, value: string) => setConfig((c: any) => ({ ...c, [field]: +value }))

  if (loading) return <div><Header title="Hire a Driver" /><div className="p-6 flex items-center justify-center h-64"><div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" /></div></div>

  return (
    <div>
      <Header title="Hire a Driver" />
      <div className="p-6 space-y-6 max-w-2xl">
        <PageHeader title="Hire a Driver" subtitle="Configure pricing for booking a driver for own vehicle" />

        <form onSubmit={save} className="space-y-4">
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6 space-y-4">
            <h3 className="font-semibold text-gray-800">Basic Pricing</h3>
            <div className="grid grid-cols-2 gap-4">
              {[
                { id: 'hBaseFare',   label: 'Base Fare (₹)',         field: 'baseFare' },
                { id: 'hFreeKm',     label: 'Free KM in Base',        field: 'baseDistance' },
                { id: 'hPerKm',      label: 'Per KM (₹)',             field: 'perKm' },
                { id: 'hPerMin',     label: 'Per Min (₹)',             field: 'perMin' },
                { id: 'hMinFare',    label: 'Min Fare (₹)',            field: 'minFare' },
                { id: 'hWaiting',    label: 'Waiting Charge (₹/min)', field: 'waitingCharge' },
                { id: 'hCancel',     label: 'Cancellation Fee (₹)',    field: 'cancellationFee' },
                { id: 'hCommission', label: 'Driver Commission (%)',   field: 'driverCommissionPercent' },
                { id: 'hMinHours',   label: 'Minimum Hours',          field: 'minHours' },
                { id: 'hHourRate',   label: 'Per Hour Rate (₹)',       field: 'perHourRate' },
              ].map(({ id, label, field }) => (
                <div key={field}>
                  <label htmlFor={id} className="block text-sm font-medium text-gray-700 mb-1">{label}</label>
                  <input id={id} type="number" step="0.5" value={config[field]}
                    onChange={e => n(field, e.target.value)}
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                </div>
              ))}
            </div>
          </div>

          <div className="flex justify-end">
            <button type="submit" disabled={saving}
              className="px-8 py-2.5 bg-primary text-white rounded-lg text-sm font-semibold hover:bg-primary-dark disabled:opacity-60">
              {saving ? 'Saving...' : 'Save Settings'}
            </button>
          </div>
        </form>
      </div>
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}

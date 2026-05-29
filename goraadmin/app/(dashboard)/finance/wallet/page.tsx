'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Toast } from '@/components/ui/toast'

export default function WalletPage() {
  const [settings, setSettings] = useState({
    minRecharge: 50,
    maxBalance: 10000,
    rechargeOptions: [100, 200, 500, 1000],
    cashEnabled: true,
    walletEnabled: true,
    commissionPercent: 20,
  })
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  useEffect(() => {
    fetch('/api/finance/wallet')
      .then(r => r.json())
      .then(d => {
        if (d && !d.error) setSettings(prev => ({ ...prev, ...d }))
        setLoading(false)
      })
      .catch(() => setLoading(false))
  }, [])

  const toggleRecharge = (amount: number) => {
    setSettings(prev => ({
      ...prev,
      rechargeOptions: (prev.rechargeOptions || []).includes(amount)
        ? (prev.rechargeOptions || []).filter(a => a !== amount)
        : [...(prev.rechargeOptions || []), amount].sort((a, b) => a - b),
    }))
  }

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    try {
      const res = await fetch('/api/finance/wallet', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(settings),
      })
      if (res.ok) setToast({ msg: 'Wallet settings saved!', type: 'success' })
      else setToast({ msg: 'Failed to save settings', type: 'error' })
    } catch {
      setToast({ msg: 'Network error', type: 'error' })
    } finally {
      setSaving(false)
    }
  }

  if (loading) return (
    <div><Header title="Wallet" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  return (
    <div>
      <Header title="Wallet" />
      <div className="p-6 space-y-6">
        <PageHeader title="Wallet Settings" subtitle="Configure wallet limits and recharge options" />

        <form onSubmit={handleSave} className="space-y-6">
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6">
            <h3 className="font-semibold text-gray-800 mb-5">Wallet Configuration</h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-5 mb-6">
              <div>
                <label htmlFor="minRecharge" className="block text-sm font-medium text-gray-700 mb-1">Minimum Recharge Amount (₹)</label>
                <input id="minRecharge" type="number" value={settings.minRecharge || 50}
                  onChange={e => setSettings({ ...settings, minRecharge: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="maxBalance" className="block text-sm font-medium text-gray-700 mb-1">Maximum Wallet Balance (₹)</label>
                <input id="maxBalance" type="number" value={settings.maxBalance || 10000}
                  onChange={e => setSettings({ ...settings, maxBalance: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="commissionPercent" className="block text-sm font-medium text-gray-700 mb-1">Commission %</label>
                <input id="commissionPercent" type="number" value={settings.commissionPercent || 20}
                  onChange={e => setSettings({ ...settings, commissionPercent: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-3">Quick Recharge Options</label>
              <div className="flex flex-wrap gap-3">
                {[50, 100, 200, 500, 1000, 2000].map(amount => (
                  <label key={amount} className="flex items-center gap-2 cursor-pointer">
                    <input type="checkbox"
                      checked={(settings.rechargeOptions || []).includes(amount)}
                      onChange={() => toggleRecharge(amount)}
                      className="w-4 h-4 text-blue-600 rounded" />
                    <span className={`px-4 py-1.5 rounded-lg text-sm font-medium border ${
                      (settings.rechargeOptions || []).includes(amount)
                        ? 'bg-blue-50 border-blue-200 text-blue-700'
                        : 'bg-gray-50 border-gray-200 text-gray-600'
                    }`}>
                      ₹{amount}
                    </span>
                  </label>
                ))}
              </div>
            </div>

            <div className="mt-5 flex justify-end">
              <button type="submit" disabled={saving}
                className="px-8 py-2.5 bg-primary text-white rounded-lg text-sm font-semibold hover:bg-primary-dark disabled:opacity-60">
                {saving ? 'Saving...' : 'Save Settings'}
              </button>
            </div>
          </div>
        </form>
      </div>
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}

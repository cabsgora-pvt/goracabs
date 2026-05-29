'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Toast } from '@/components/ui/toast'

const tabs = ['Razorpay', 'Stripe', 'Cash & Wallet']

export default function PaymentSettingsPage() {
  const [settings, setSettings] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [activeTab, setActiveTab] = useState('Razorpay')
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  useEffect(() => {
    fetch('/api/settings').then(r => r.json()).then(data => { setSettings(data); setLoading(false) })
  }, [])

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    try {
      await fetch('/api/settings', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(settings) })
      setToast({ msg: 'Payment settings saved!', type: 'success' })
    } catch {
      setToast({ msg: 'Failed to save', type: 'error' })
    } finally {
      setSaving(false)
    }
  }

  const update = (path: string[], value: any) => {
    setSettings((prev: any) => {
      const copy = JSON.parse(JSON.stringify(prev))
      let obj = copy
      for (let i = 0; i < path.length - 1; i++) obj = obj[path[i]]
      obj[path[path.length - 1]] = value
      return copy
    })
  }

  if (loading) return (
    <div>
      <Header title="Payment Settings" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  return (
    <div>
      <Header title="Payment Settings" />
      <div className="p-6 space-y-6">
        <PageHeader title="Payment Settings" subtitle="Configure payment gateways and options" />

        <div className="flex gap-1 bg-gray-100 p-1 rounded-xl w-fit">
          {tabs.map(t => (
            <button key={t} onClick={() => setActiveTab(t)}
              className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${activeTab === t ? 'bg-white text-gray-800 shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}>
              {t}
            </button>
          ))}
        </div>

        <form onSubmit={handleSave}>
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6 space-y-5">
            {activeTab === 'Razorpay' && (
              <>
                <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                  <div>
                    <p className="font-medium text-gray-800">Enable Razorpay</p>
                    <p className="text-sm text-gray-500">Accept UPI, cards, and net banking</p>
                  </div>
                  <button type="button"
                    onClick={() => update(['payment', 'razorpay', 'enabled'], !settings?.payment?.razorpay?.enabled)}
                    className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${settings?.payment?.razorpay?.enabled ? 'bg-primary' : 'bg-gray-200'}`}>
                    <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow-sm transition-transform ${settings?.payment?.razorpay?.enabled ? 'translate-x-6' : 'translate-x-1'}`} />
                  </button>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Key ID</label>
                  <input value={settings?.payment?.razorpay?.keyId || ''}
                    onChange={e => update(['payment', 'razorpay', 'keyId'], e.target.value)}
                    placeholder="rzp_live_..."
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono" />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Key Secret</label>
                  <input type="password" value={settings?.payment?.razorpay?.keySecret || ''}
                    onChange={e => update(['payment', 'razorpay', 'keySecret'], e.target.value)}
                    placeholder="••••••••"
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                </div>
              </>
            )}

            {activeTab === 'Stripe' && (
              <>
                <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                  <div>
                    <p className="font-medium text-gray-800">Enable Stripe</p>
                    <p className="text-sm text-gray-500">Accept international cards</p>
                  </div>
                  <button type="button"
                    onClick={() => update(['payment', 'stripe', 'enabled'], !settings?.payment?.stripe?.enabled)}
                    className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${settings?.payment?.stripe?.enabled ? 'bg-primary' : 'bg-gray-200'}`}>
                    <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow-sm transition-transform ${settings?.payment?.stripe?.enabled ? 'translate-x-6' : 'translate-x-1'}`} />
                  </button>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Publishable Key</label>
                  <input value={settings?.payment?.stripe?.publishableKey || ''}
                    onChange={e => update(['payment', 'stripe', 'publishableKey'], e.target.value)}
                    placeholder="pk_live_..."
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono" />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Secret Key</label>
                  <input type="password" value={settings?.payment?.stripe?.secretKey || ''}
                    onChange={e => update(['payment', 'stripe', 'secretKey'], e.target.value)}
                    placeholder="sk_live_..."
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                </div>
              </>
            )}

            {activeTab === 'Cash & Wallet' && (
              <>
                {[
                  { label: 'Enable Cash Payments', desc: 'Allow riders to pay with cash', key: 'cashEnabled' },
                  { label: 'Enable Wallet', desc: 'Allow users to use app wallet', key: 'walletEnabled' },
                ].map(opt => (
                  <div key={opt.key} className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                    <div>
                      <p className="font-medium text-gray-800">{opt.label}</p>
                      <p className="text-sm text-gray-500">{opt.desc}</p>
                    </div>
                    <button type="button"
                      onClick={() => update(['payment', opt.key], !settings?.payment?.[opt.key])}
                      className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${settings?.payment?.[opt.key] ? 'bg-primary' : 'bg-gray-200'}`}>
                      <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow-sm transition-transform ${settings?.payment?.[opt.key] ? 'translate-x-6' : 'translate-x-1'}`} />
                    </button>
                  </div>
                ))}
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Platform Commission: <strong>{settings?.payment?.commissionPercent}%</strong>
                  </label>
                  <input type="range" min="5" max="40" step="1"
                    value={settings?.payment?.commissionPercent || 20}
                    onChange={e => update(['payment', 'commissionPercent'], +e.target.value)}
                    className="w-full accent-primary" />
                  <div className="flex justify-between text-xs text-gray-400 mt-1">
                    <span>5%</span><span>40%</span>
                  </div>
                </div>
              </>
            )}

            <div className="flex justify-end pt-2 border-t border-gray-100">
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

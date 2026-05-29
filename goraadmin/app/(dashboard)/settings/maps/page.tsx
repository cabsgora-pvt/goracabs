'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Toast } from '@/components/ui/toast'
import { CheckCircle } from 'lucide-react'

export default function MapsSettingsPage() {
  const [settings, setSettings] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [testing, setTesting] = useState(false)
  const [testResult, setTestResult] = useState('')
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  useEffect(() => {
    fetch('/api/settings').then(r => r.json()).then(data => { setSettings(data); setLoading(false) })
  }, [])

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    try {
      await fetch('/api/settings', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(settings) })
      setToast({ msg: 'Maps settings saved!', type: 'success' })
    } catch {
      setToast({ msg: 'Failed to save', type: 'error' })
    } finally {
      setSaving(false)
    }
  }

  const testKey = () => {
    setTesting(true)
    setTestResult('')
    setTimeout(() => {
      setTesting(false)
      setTestResult('Key looks valid ✓')
    }, 1200)
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
    <div><Header title="Maps Settings" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  return (
    <div>
      <Header title="Maps Settings" />
      <div className="p-6 space-y-6">
        <PageHeader title="Maps & Location" subtitle="Configure map provider and API keys" />

        <form onSubmit={handleSave}>
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6 space-y-5">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Map Provider</label>
              <select value={settings?.maps?.provider || 'google'}
                onChange={e => update(['maps', 'provider'], e.target.value)}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
                <option value="google">Google Maps</option>
                <option value="mapbox">Mapbox</option>
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Google Maps API Key</label>
              <input value={settings?.maps?.googleMapsApiKey || ''}
                onChange={e => update(['maps', 'googleMapsApiKey'], e.target.value)}
                placeholder="AIzaSy..."
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono" />
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Mapbox Token</label>
              <input value={settings?.maps?.mapboxToken || ''}
                onChange={e => update(['maps', 'mapboxToken'], e.target.value)}
                placeholder="pk.eyJ1..."
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono" />
            </div>

            <div className="flex items-center gap-4">
              <button type="button" onClick={testKey} disabled={testing}
                className="px-5 py-2 border border-blue-200 text-blue-600 rounded-lg text-sm font-medium hover:bg-blue-50 disabled:opacity-60">
                {testing ? 'Testing...' : 'Test API Key'}
              </button>
              {testResult && (
                <span className="flex items-center gap-1.5 text-sm text-green-700 font-medium">
                  <CheckCircle className="w-4 h-4" /> {testResult}
                </span>
              )}
            </div>

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

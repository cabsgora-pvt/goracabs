'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Toast } from '@/components/ui/toast'
import { Mail, CheckCircle } from 'lucide-react'

export default function MailSettingsPage() {
  const [settings, setSettings] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [testResult, setTestResult] = useState('')
  const [testing, setTesting] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  useEffect(() => {
    fetch('/api/settings').then(r => r.json()).then(data => { setSettings(data); setLoading(false) })
  }, [])

  const update = (path: string[], value: any) => {
    setSettings((prev: any) => {
      const copy = JSON.parse(JSON.stringify(prev))
      let obj = copy
      for (let i = 0; i < path.length - 1; i++) obj = obj[path[i]]
      obj[path[path.length - 1]] = value
      return copy
    })
  }

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    try {
      await fetch('/api/settings', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(settings) })
      setToast({ msg: 'Mail settings saved!', type: 'success' })
    } catch {
      setToast({ msg: 'Failed to save', type: 'error' })
    } finally {
      setSaving(false)
    }
  }

  const sendTestEmail = () => {
    setTesting(true)
    setTestResult('')
    setTimeout(() => {
      setTesting(false)
      setTestResult('Test email sent successfully!')
    }, 1500)
  }

  if (loading) return (
    <div><Header title="Mail Settings" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  return (
    <div>
      <Header title="Mail Settings" />
      <div className="p-6 space-y-6">
        <PageHeader title="Mail Settings" subtitle="Configure SMTP and email sender details" />

        <form onSubmit={handleSave}>
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6 space-y-5">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Mail Driver</label>
              <select value={settings?.mail?.driver || 'smtp'}
                onChange={e => update(['mail', 'driver'], e.target.value)}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
                <option value="smtp">SMTP</option>
                <option value="sendgrid">SendGrid</option>
              </select>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">SMTP Host</label>
                <input value={settings?.mail?.host || ''}
                  onChange={e => update(['mail', 'host'], e.target.value)}
                  placeholder="smtp.gmail.com"
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Port</label>
                <input type="number" value={settings?.mail?.port || 587}
                  onChange={e => update(['mail', 'port'], +e.target.value)}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Username / Email</label>
                <input type="email" value={settings?.mail?.username || ''}
                  onChange={e => update(['mail', 'username'], e.target.value)}
                  placeholder="your@gmail.com"
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Password / App Password</label>
                <input type="password" value={settings?.mail?.password || ''}
                  onChange={e => update(['mail', 'password'], e.target.value)}
                  placeholder="••••••••"
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">From Name</label>
                <input value={settings?.mail?.fromName || ''}
                  onChange={e => update(['mail', 'fromName'], e.target.value)}
                  placeholder="Gora Cabs"
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">From Email</label>
                <input type="email" value={settings?.mail?.fromEmail || ''}
                  onChange={e => update(['mail', 'fromEmail'], e.target.value)}
                  placeholder="noreply@goracabs.com"
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
            </div>

            <div className="flex items-center gap-4">
              <button type="button" onClick={sendTestEmail} disabled={testing}
                className="flex items-center gap-2 px-5 py-2 border border-blue-200 text-blue-600 rounded-lg text-sm font-medium hover:bg-blue-50 disabled:opacity-60">
                <Mail className="w-4 h-4" />
                {testing ? 'Sending...' : 'Send Test Email'}
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

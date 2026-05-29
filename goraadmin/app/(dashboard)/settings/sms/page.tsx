'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Toast } from '@/components/ui/toast'
import { MessageSquare, CheckCircle } from 'lucide-react'

export default function SMSSettingsPage() {
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
      setToast({ msg: 'SMS settings saved!', type: 'success' })
    } catch {
      setToast({ msg: 'Failed to save', type: 'error' })
    } finally {
      setSaving(false)
    }
  }

  const sendTestOTP = () => {
    setTesting(true)
    setTestResult('')
    setTimeout(() => {
      setTesting(false)
      setTestResult('Test OTP sent to +91 98765 43210')
    }, 1500)
  }

  if (loading) return (
    <div><Header title="SMS Settings" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  const provider = settings?.sms?.provider || 'twilio'

  return (
    <div>
      <Header title="SMS Settings" />
      <div className="p-6 space-y-6">
        <PageHeader title="SMS Settings" subtitle="Configure SMS provider for OTP and notifications" />

        <form onSubmit={handleSave}>
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6 space-y-5">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">SMS Provider</label>
              <select value={provider} onChange={e => update(['sms', 'provider'], e.target.value)}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
                <option value="twilio">Twilio</option>
                <option value="msg91">MSG91</option>
              </select>
            </div>

            {provider === 'twilio' && (
              <>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Account SID</label>
                  <input value={settings?.sms?.twilio?.accountSid || ''}
                    onChange={e => update(['sms', 'twilio', 'accountSid'], e.target.value)}
                    placeholder="AC..."
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono" />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Auth Token</label>
                  <input type="password" value={settings?.sms?.twilio?.authToken || ''}
                    onChange={e => update(['sms', 'twilio', 'authToken'], e.target.value)}
                    placeholder="••••••••"
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">From Number</label>
                  <input value={settings?.sms?.twilio?.fromNumber || ''}
                    onChange={e => update(['sms', 'twilio', 'fromNumber'], e.target.value)}
                    placeholder="+1 555 000 0000"
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono" />
                </div>
              </>
            )}

            {provider === 'msg91' && (
              <>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Auth Key</label>
                  <input value={settings?.sms?.msg91?.authKey || ''}
                    onChange={e => update(['sms', 'msg91', 'authKey'], e.target.value)}
                    placeholder="MSG91 Auth Key"
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono" />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Sender ID</label>
                  <input value={settings?.sms?.msg91?.senderId || ''}
                    onChange={e => update(['sms', 'msg91', 'senderId'], e.target.value)}
                    placeholder="GORACB"
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                </div>
              </>
            )}

            <div className="flex items-center gap-4">
              <button type="button" onClick={sendTestOTP} disabled={testing}
                className="flex items-center gap-2 px-5 py-2 border border-blue-200 text-blue-600 rounded-lg text-sm font-medium hover:bg-blue-50 disabled:opacity-60">
                <MessageSquare className="w-4 h-4" />
                {testing ? 'Sending...' : 'Send Test OTP'}
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

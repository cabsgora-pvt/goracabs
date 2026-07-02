'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Toast } from '@/components/ui/toast'
import { MessageSquare, CheckCircle, XCircle } from 'lucide-react'

export default function SMSSettingsPage() {
  const [settings, setSettings] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [testPhone, setTestPhone] = useState('')
  const [testResult, setTestResult] = useState<{ ok: boolean; msg: string } | null>(null)
  const [testing, setTesting] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  useEffect(() => {
    fetch('/api/settings').then(r => r.json()).then(data => { setSettings(data); setLoading(false) })
  }, [])

  const update = (path: string[], value: any) => {
    setSettings((prev: any) => {
      const copy = JSON.parse(JSON.stringify(prev))
      let obj = copy
      for (let i = 0; i < path.length - 1; i++) {
        if (obj[path[i]] == null) obj[path[i]] = {}
        obj = obj[path[i]]
      }
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

  const sendTestOTP = async () => {
    if (!testPhone || testPhone.replace(/\D/g, '').length < 10) {
      setTestResult({ ok: false, msg: 'Enter a valid 10-digit number' })
      return
    }
    setTesting(true)
    setTestResult(null)
    try {
      const res = await fetch('/api/settings/test-sms', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ phone: testPhone }),
      })
      const data = await res.json()
      setTestResult({ ok: !!data.success, msg: data.success ? `Test OTP sent to ${testPhone}` : (data.message || 'Failed to send') })
    } catch (err: any) {
      setTestResult({ ok: false, msg: 'Request failed' })
    } finally {
      setTesting(false)
    }
  }

  if (loading) return (
    <div><Header title="SMS Settings" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  const provider = settings?.sms?.provider || 'smsindori'
  const inputCls = 'w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500'

  return (
    <div>
      <Header title="SMS Settings" />
      <div className="p-6 space-y-6">
        <PageHeader title="SMS Settings" subtitle="Configure SMS provider for OTP and notifications" />

        <form onSubmit={handleSave}>
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6 space-y-5">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">SMS Provider</label>
              <select aria-label="SMS Provider" value={provider} onChange={e => update(['sms', 'provider'], e.target.value)}
                className={`${inputCls} bg-white`}>
                <option value="smsindori">SMS Indori</option>
                <option value="twilio">Twilio</option>
                <option value="msg91">MSG91</option>
              </select>
            </div>

            {provider === 'smsindori' && (
              <>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Auth Key (authentic-key)</label>
                  <input value={settings?.sms?.smsindori?.authKey || ''}
                    onChange={e => update(['sms', 'smsindori', 'authKey'], e.target.value)}
                    placeholder="373543616273676f7261..." title="SMS Indori Auth Key"
                    className={`${inputCls} font-mono`} />
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-1">Sender ID (6 char)</label>
                    <input value={settings?.sms?.smsindori?.senderId || ''}
                      onChange={e => update(['sms', 'smsindori', 'senderId'], e.target.value)}
                      placeholder="GORAOT" title="DLT approved Sender ID" className={inputCls} />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-1">Route ID</label>
                    <input value={settings?.sms?.smsindori?.route || ''}
                      onChange={e => update(['sms', 'smsindori', 'route'], e.target.value)}
                      placeholder="16 (TransOTP)" title="Route ID" className={inputCls} />
                  </div>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">DLT Template ID</label>
                  <input value={settings?.sms?.smsindori?.templateId || ''}
                    onChange={e => update(['sms', 'smsindori', 'templateId'], e.target.value)}
                    placeholder="1107177495369252598" title="DLT Template ID" className={`${inputCls} font-mono`} />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Template Text (must match DLT)</label>
                  <textarea value={settings?.sms?.smsindori?.templateText || ''}
                    onChange={e => update(['sms', 'smsindori', 'templateText'], e.target.value)}
                    rows={3} title="DLT Template Text"
                    placeholder="Your Gora Cabs OTP is {#numeric#}. It is valid for 5 minutes. Do not share it with anyone."
                    className={inputCls} />
                  <p className="text-xs text-gray-500 mt-1">Use <code className="bg-gray-100 px-1 rounded">{'{#numeric#}'}</code> where the OTP goes. Text must exactly match your approved DLT template.</p>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">API URL</label>
                  <input value={settings?.sms?.smsindori?.apiUrl || ''}
                    onChange={e => update(['sms', 'smsindori', 'apiUrl'], e.target.value)}
                    placeholder="http://sms.smsindori.com/http-tokenkeyapi.php" title="API URL"
                    className={`${inputCls} font-mono`} />
                </div>
              </>
            )}

            {provider === 'twilio' && (
              <>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Account SID</label>
                  <input value={settings?.sms?.twilio?.accountSid || ''}
                    onChange={e => update(['sms', 'twilio', 'accountSid'], e.target.value)}
                    placeholder="AC..." title="Twilio Account SID" className={`${inputCls} font-mono`} />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Auth Token</label>
                  <input type="password" value={settings?.sms?.twilio?.authToken || ''}
                    onChange={e => update(['sms', 'twilio', 'authToken'], e.target.value)}
                    placeholder="••••••••" title="Twilio Auth Token" className={inputCls} />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">From Number</label>
                  <input value={settings?.sms?.twilio?.fromNumber || ''}
                    onChange={e => update(['sms', 'twilio', 'fromNumber'], e.target.value)}
                    placeholder="+1 555 000 0000" title="Twilio From Number" className={`${inputCls} font-mono`} />
                </div>
              </>
            )}

            {provider === 'msg91' && (
              <>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Auth Key</label>
                  <input value={settings?.sms?.msg91?.authKey || ''}
                    onChange={e => update(['sms', 'msg91', 'authKey'], e.target.value)}
                    placeholder="MSG91 Auth Key" title="MSG91 Auth Key" className={`${inputCls} font-mono`} />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Sender ID</label>
                  <input value={settings?.sms?.msg91?.senderId || ''}
                    onChange={e => update(['sms', 'msg91', 'senderId'], e.target.value)}
                    placeholder="GORACB" title="MSG91 Sender ID" className={inputCls} />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">DLT Template ID (optional)</label>
                  <input value={settings?.sms?.msg91?.templateId || ''}
                    onChange={e => update(['sms', 'msg91', 'templateId'], e.target.value)}
                    placeholder="DLT Template ID" title="MSG91 Template ID" className={`${inputCls} font-mono`} />
                </div>
              </>
            )}

            <div className="border-t border-gray-100 pt-4 space-y-3">
              <label className="block text-sm font-medium text-gray-700">Test OTP (save settings first)</label>
              <div className="flex flex-wrap items-center gap-3">
                <input value={testPhone} onChange={e => setTestPhone(e.target.value)}
                  placeholder="10-digit number" title="Test phone number"
                  className={`${inputCls} max-w-[220px]`} />
                <button type="button" onClick={sendTestOTP} disabled={testing}
                  className="flex items-center gap-2 px-5 py-2 border border-blue-200 text-blue-600 rounded-lg text-sm font-medium hover:bg-blue-50 disabled:opacity-60">
                  <MessageSquare className="w-4 h-4" />
                  {testing ? 'Sending...' : 'Send Test OTP'}
                </button>
                {testResult && (
                  <span className={`flex items-center gap-1.5 text-sm font-medium ${testResult.ok ? 'text-green-700' : 'text-red-600'}`}>
                    {testResult.ok ? <CheckCircle className="w-4 h-4" /> : <XCircle className="w-4 h-4" />} {testResult.msg}
                  </span>
                )}
              </div>
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

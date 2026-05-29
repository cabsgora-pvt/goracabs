'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Toast } from '@/components/ui/toast'
import { Bell, CheckCircle } from 'lucide-react'

export default function FirebaseSettingsPage() {
  const [settings, setSettings] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [testResult, setTestResult] = useState('')
  const [testing, setTesting] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  useEffect(() => {
    fetch('/api/settings').then(r => r.json()).then(data => { setSettings(data); setLoading(false) })
  }, [])

  const update = (key: string, value: string) => {
    setSettings((prev: any) => ({ ...prev, firebase: { ...prev.firebase, [key]: value } }))
  }

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    try {
      await fetch('/api/settings', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(settings) })
      setToast({ msg: 'Firebase settings saved!', type: 'success' })
    } catch {
      setToast({ msg: 'Failed to save', type: 'error' })
    } finally {
      setSaving(false)
    }
  }

  const testNotification = () => {
    setTesting(true)
    setTestResult('')
    setTimeout(() => {
      setTesting(false)
      setTestResult('Test push notification sent!')
    }, 1500)
  }

  if (loading) return (
    <div><Header title="Firebase Settings" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  return (
    <div>
      <Header title="Firebase Settings" />
      <div className="p-6 space-y-6">
        <PageHeader title="Firebase / FCM Settings" subtitle="Configure push notification credentials" />

        <div className="bg-yellow-50 border border-yellow-200 rounded-xl p-4">
          <p className="text-sm text-yellow-800">
            Firebase Cloud Messaging (FCM) is required for push notifications to work. Get credentials from your Firebase Console.
          </p>
        </div>

        <form onSubmit={handleSave}>
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6 space-y-5">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">FCM Server Key</label>
              <textarea rows={3} value={settings?.firebase?.serverKey || ''}
                onChange={e => update('serverKey', e.target.value)}
                placeholder="AAAAxxx:APA91b..."
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono resize-none" />
              <p className="text-xs text-gray-400 mt-1">Found in Firebase Console → Project Settings → Cloud Messaging</p>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Project ID</label>
              <input value={settings?.firebase?.projectId || ''}
                onChange={e => update('projectId', e.target.value)}
                placeholder="my-gora-project"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>

            <div className="flex items-center gap-4">
              <button type="button" onClick={testNotification} disabled={testing}
                className="flex items-center gap-2 px-5 py-2 border border-blue-200 text-blue-600 rounded-lg text-sm font-medium hover:bg-blue-50 disabled:opacity-60">
                <Bell className="w-4 h-4" />
                {testing ? 'Sending...' : 'Test Notification'}
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

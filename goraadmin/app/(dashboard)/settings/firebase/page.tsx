'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Toast } from '@/components/ui/toast'
import { Bell, CheckCircle, AlertCircle } from 'lucide-react'

export default function FirebaseSettingsPage() {
  const [settings, setSettings] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [testResult, setTestResult] = useState('')
  const [testOk, setTestOk] = useState<boolean | null>(null)
  const [testToken, setTestToken] = useState('')
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

  // Really verifies the service account against Google. This used to be a 1.5 s
  // setTimeout that always reported success, which made a broken push setup look
  // healthy — the exact opposite of what a test button is for. Saves first, so
  // what is on screen is what gets tested.
  const testNotification = async () => {
    setTesting(true)
    setTestResult('')
    setTestOk(null)
    try {
      await fetch('/api/settings', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(settings),
      })
      const res = await fetch('/api/settings/test-push', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: testToken.trim() || undefined }),
      })
      const data = await res.json().catch(() => ({}))
      setTestOk(!!data.ok)
      setTestResult(data.message || (res.ok ? 'Push is live.' : 'Verification failed.'))
    } catch {
      setTestOk(false)
      setTestResult('Could not reach the server.')
    } finally {
      setTesting(false)
    }
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

        <div className="bg-yellow-50 border border-yellow-200 rounded-xl p-4 space-y-2">
          <p className="text-sm text-yellow-800">
            Until all three fields below are filled in, every push is a silent no-op and both apps
            fall back to polling &mdash; which means a driver only sees a ride request while the app
            is open and awake.
          </p>
          <p className="text-sm text-yellow-800">
            Get them from <strong>Firebase Console &rarr; Project Settings &rarr; Service accounts
            &rarr; Generate new private key</strong>. Open the downloaded JSON and copy its
            <code className="mx-1 px-1 bg-yellow-100 rounded">project_id</code>,
            <code className="mx-1 px-1 bg-yellow-100 rounded">client_email</code> and
            <code className="mx-1 px-1 bg-yellow-100 rounded">private_key</code> values.
          </p>
        </div>

        <form onSubmit={handleSave}>
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6 space-y-5">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Project ID</label>
              <input value={settings?.firebase?.projectId || ''}
                onChange={e => update('projectId', e.target.value)}
                placeholder="my-gora-project"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              <p className="text-xs text-gray-400 mt-1">JSON field: project_id</p>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Client Email</label>
              <input value={settings?.firebase?.clientEmail || ''}
                onChange={e => update('clientEmail', e.target.value)}
                placeholder="firebase-adminsdk-xxxxx@my-gora-project.iam.gserviceaccount.com"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono" />
              <p className="text-xs text-gray-400 mt-1">JSON field: client_email</p>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Private Key</label>
              <textarea rows={5} value={settings?.firebase?.privateKey || ''}
                onChange={e => update('privateKey', e.target.value)}
                placeholder="-----BEGIN PRIVATE KEY-----  MIIEv...  -----END PRIVATE KEY-----"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono resize-none" />
              <p className="text-xs text-gray-400 mt-1">
                JSON field: private_key. Paste it whole &mdash; literal backslash-n escapes are handled.
              </p>
            </div>

            <div className="text-xs text-gray-500 border-t border-gray-100 pt-4">
              Used only when <code className="px-1 bg-gray-100 rounded">FCM_PROJECT_ID</code>,{' '}
              <code className="px-1 bg-gray-100 rounded">FCM_CLIENT_EMAIL</code> and{' '}
              <code className="px-1 bg-gray-100 rounded">FCM_PRIVATE_KEY</code> are not set in the
              environment &mdash; env always wins. Saved changes take effect within a minute; no restart needed.
            </div>

            <div className="border-t border-gray-100 pt-5 space-y-3">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Device token <span className="font-normal text-gray-400">(optional)</span>
                </label>
                <input value={testToken} onChange={e => setTestToken(e.target.value)}
                  placeholder="Paste a driver or rider FCM token to send a real notification"
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono" />
                <p className="text-xs text-gray-400 mt-1">
                  Leave blank to only verify the credentials against Google.
                </p>
              </div>

              <div className="flex items-start gap-4">
                <button type="button" onClick={testNotification} disabled={testing}
                  className="flex items-center gap-2 px-5 py-2 border border-blue-200 text-blue-600 rounded-lg text-sm font-medium hover:bg-blue-50 disabled:opacity-60 shrink-0">
                  <Bell className="w-4 h-4" />
                  {testing ? 'Checking...' : 'Test Push'}
                </button>
                {testResult && (
                  <span className={`flex items-start gap-1.5 text-sm font-medium pt-2 ${testOk ? 'text-green-700' : 'text-red-700'}`}>
                    {testOk
                      ? <CheckCircle className="w-4 h-4 shrink-0 mt-0.5" />
                      : <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />}
                    {testResult}
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

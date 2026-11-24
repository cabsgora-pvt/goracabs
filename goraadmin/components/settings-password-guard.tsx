'use client'
import { useEffect, useRef, useState } from 'react'
import { Lock } from 'lucide-react'

// Every settings change needs the admin's password again. Rather than touch
// each settings page, this wraps window.fetch once: a POST/PUT to
// /api/settings or /api/settings/franchise first asks for the password, sends
// it in X-Admin-Password, and asks again if it was wrong. Cancelling rejects
// the fetch, so a page never shows "Saved" for a change that was not made.
// A correct password is remembered for 2 minutes (one save + its test call).
const GUARDED = /^\/api\/settings(\/franchise)?\/?(\?.*)?$/
const REMEMBER_MS = 2 * 60 * 1000

type Ask = { resolve: (pwd: string | null) => void; wrong: boolean }

export function SettingsPasswordGuard() {
  const [ask, setAsk] = useState<Ask | null>(null)
  const [pwd, setPwd] = useState('')
  const remembered = useRef<{ pwd: string; until: number } | null>(null)
  const askRef = useRef<(wrong: boolean) => Promise<string | null>>()

  askRef.current = (wrong: boolean) => new Promise(resolve => { setPwd(''); setAsk({ resolve, wrong }) })

  useEffect(() => {
    const original = window.fetch
    const guarded: typeof window.fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.pathname + input.search : (input as Request).url
      let path = url
      try { path = new URL(url, window.location.origin).pathname } catch {}
      const method = (init?.method || (input instanceof Request ? input.method : 'GET')).toUpperCase()
      if (!GUARDED.test(path) || (method !== 'POST' && method !== 'PUT')) return original(input, init)

      let wrong = false
      for (;;) {
        let password = remembered.current && remembered.current.until > Date.now() ? remembered.current.pwd : null
        if (!password) {
          password = await askRef.current!(wrong)
          if (!password) throw new Error('Settings not saved: password not entered')
        }
        const headers = new Headers(init?.headers || (input instanceof Request ? input.headers : undefined))
        headers.set('X-Admin-Password', password)
        const res = await original(input, { ...init, headers })
        if (res.status === 403 || res.status === 428) {
          const body = await res.clone().json().catch(() => ({}))
          if (body?.needsPassword) { remembered.current = null; wrong = !!body.wrongPassword; continue }
        }
        if (res.ok) remembered.current = { pwd: password, until: Date.now() + REMEMBER_MS }
        return res
      }
    }
    window.fetch = guarded
    return () => { window.fetch = original }
  }, [])

  if (!ask) return null
  const done = (v: string | null) => { ask.resolve(v); setAsk(null) }
  return (
    <div className="fixed inset-0 z-[100] bg-black/40 flex items-center justify-center p-4" role="dialog" aria-modal="true" aria-label="Confirm password">
      <form className="bg-white rounded-xl shadow-xl w-full max-w-sm p-6 space-y-4"
        onSubmit={e => { e.preventDefault(); if (pwd) done(pwd) }}>
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-full bg-primary/10 text-primary flex items-center justify-center"><Lock className="w-5 h-5" /></div>
          <div>
            <p className="font-semibold text-gray-900">Confirm it&apos;s you</p>
            <p className="text-xs text-gray-500">Enter your admin password to save these settings.</p>
          </div>
        </div>
        <input type="password" autoFocus value={pwd} onChange={e => setPwd(e.target.value)} placeholder="Password"
          aria-label="Admin password"
          className={`w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 ${ask.wrong ? 'border-red-400 focus:ring-red-300' : 'border-gray-300 focus:ring-blue-500'}`} />
        {ask.wrong && <p className="text-xs text-red-600 -mt-2">Wrong password — try again.</p>}
        <div className="flex justify-end gap-2">
          <button type="button" onClick={() => done(null)} className="px-4 py-2 border rounded-lg text-sm">Cancel</button>
          <button type="submit" disabled={!pwd} className="px-4 py-2 bg-primary text-white rounded-lg text-sm font-semibold disabled:opacity-50">Confirm &amp; save</button>
        </div>
      </form>
    </div>
  )
}

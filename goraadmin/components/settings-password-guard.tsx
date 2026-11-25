'use client'
import { useEffect, useRef, useState } from 'react'
import { Lock } from 'lucide-react'

// Settings, money, pricing and destructive admin changes need the admin's
// password again (server: lib/admin-password). Rather than touch each page,
// this wraps window.fetch once:
//   • a POST/PUT/PATCH/DELETE to a GUARDED route asks for the password first,
//     unless a correct one was given in the last few minutes (the server keeps
//     a 5-minute "sudo" window for this session, so no password is kept here);
//   • any admin API that still answers 428/403 { needsPassword } — the window
//     ran out, or the route is guarded but not listed below — asks and retries.
// Cancelling rejects the fetch, so a page never shows "Saved" for a change
// that was not made.
const ALL = ['POST', 'PUT', 'PATCH', 'DELETE']
const GUARDED: [RegExp, string[]][] = [
  ...[
    'settings(/franchise)?', 'app-config', 'finance/wallet',
    'services/[^/]+', 'zones/[^/]+/(pricing|rental-packages)', 'vehicles/types(/[^/]+)?',
    'surge(/[^/]+)?', 'promos(/[^/]+)?', 'subscription-plans(/[^/]+)?', 'zone-plans(/[^/]+)?',
    'incentives(/[^/]+)?', 'drivers/[^/]+/wallet', 'wallet/admin', 'finance/withdrawals/[^/]+',
    'zone-admins/[^/]+/(payouts|subscription)', 'rides/[^/]+/(force-complete|otp-unlock)',
    'document-types(/[^/]+)?', 'ride-preferences(/[^/]+)?',
  ].map(p => [new RegExp(`^/api/(${p})/?$`), ALL] as [RegExp, string[]]),
  [/^\/api\/notifications\/?$/, ['POST']],
  // Deleting an account. A driver PUT that changes bank details is guarded
  // server-side and prompts through the 428 fallback below.
  [/^\/api\/(users|drivers)\/[^/]+\/?$/, ['DELETE']],
]
const isGuarded = (path: string, method: string) => GUARDED.some(([re, m]) => m.includes(method) && re.test(path))
const METHODS = new Set(ALL)
const SUDO_CLIENT_MS = 4.5 * 60 * 1000   // a little under the server's 5 minutes

type Ask = { resolve: (pwd: string | null) => void; wrong: boolean }

export function SettingsPasswordGuard() {
  const [ask, setAsk] = useState<Ask | null>(null)
  const [pwd, setPwd] = useState('')
  const sudoUntil = useRef(0)
  const askRef = useRef<(wrong: boolean) => Promise<string | null>>()

  askRef.current = (wrong: boolean) => new Promise(resolve => { setPwd(''); setAsk({ resolve, wrong }) })

  useEffect(() => {
    const original = window.fetch
    // The session was revoked (logout elsewhere) or expired: clear the cookie
    // and go to sign-in instead of showing empty pages.
    let leaving = false
    const signedOutCheck = (res: Response) => {
      if (res.status === 401 && !leaving) {
        leaving = true
        original('/api/auth/logout', { method: 'POST', credentials: 'same-origin' })
          .catch(() => {}).finally(() => { window.location.href = '/login' })
      }
      return res
    }
    const guarded: typeof window.fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.pathname + input.search : (input as Request).url
      let path = url
      try { path = new URL(url, window.location.origin).pathname } catch {}
      const method = (init?.method || (input instanceof Request ? input.method : 'GET')).toUpperCase()
      if (!path.startsWith('/api/') || path.startsWith('/api/auth/')) return original(input, init)
      if (!METHODS.has(method)) return signedOutCheck(await original(input, init))

      let password: string | null = null
      let wrong = false
      if (isGuarded(path, method) && sudoUntil.current < Date.now()) {
        password = await askRef.current!(false)
        if (!password) throw new Error('Not saved: password not entered')
      }
      for (;;) {
        const headers = new Headers(init?.headers || (input instanceof Request ? input.headers : undefined))
        if (password) headers.set('X-Admin-Password', password)
        const res = await original(input, { ...init, headers })
        if (res.status === 403 || res.status === 428) {
          const body = await res.clone().json().catch(() => ({}))
          if (body?.needsPassword) {
            sudoUntil.current = 0
            wrong = !!body.wrongPassword
            password = await askRef.current!(wrong)
            if (!password) throw new Error('Not saved: password not entered')
            continue
          }
        }
        if (res.ok && password) sudoUntil.current = Date.now() + SUDO_CLIENT_MS
        return signedOutCheck(res)
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
            <p className="text-xs text-gray-500">Enter your admin password to confirm this change. You won&apos;t be asked again for 5 minutes.</p>
          </div>
        </div>
        <input type="password" autoFocus value={pwd} onChange={e => setPwd(e.target.value)} placeholder="Password"
          aria-label="Admin password"
          className={`w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 ${ask.wrong ? 'border-red-400 focus:ring-red-300' : 'border-gray-300 focus:ring-blue-500'}`} />
        {ask.wrong && <p className="text-xs text-red-600 -mt-2">Wrong password — try again.</p>}
        <div className="flex justify-end gap-2">
          <button type="button" onClick={() => done(null)} className="px-4 py-2 border rounded-lg text-sm">Cancel</button>
          <button type="submit" disabled={!pwd} className="px-4 py-2 bg-primary text-white rounded-lg text-sm font-semibold disabled:opacity-50">Confirm</button>
        </div>
      </form>
    </div>
  )
}

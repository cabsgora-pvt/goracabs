'use client'
import { useState } from 'react'
import { useRouter } from 'next/navigation'

// Sign-in for zone admins (franchise). Same look as the super admin sign-in.
export default function ZoneLoginPage() {
  const router = useRouter()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [info, setInfo] = useState('')

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    if (!email || !password) { setError('Please enter email and password'); return }
    setLoading(true)
    try {
      const res = await fetch('/api/zone-admin/login', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }),
      })
      const d = await res.json()
      if (!res.ok) { setError(d.error || 'Login failed'); return }
      router.push('/zone-panel')
    } catch {
      setError('Network error. Please try again.')
    } finally { setLoading(false) }
  }

  const field = 'w-full border border-[#ced4da] rounded px-3 py-2.5 text-[13px] text-[#212529] focus:outline-none focus:border-[#a0a8c4]'
  return (
    <div className="min-h-screen relative flex flex-col items-center" style={{ backgroundColor: '#f3f3f9' }}>
      <div className="absolute top-0 left-0 right-0 h-[380px] overflow-hidden" style={{ background: 'linear-gradient(to right, #364574, #405189)' }}>
        <svg className="absolute bottom-0 left-0 w-full" viewBox="0 0 1440 120" preserveAspectRatio="none" aria-hidden="true">
          <path d="M0,64 C360,128 1080,0 1440,64 L1440,120 L0,120 Z" fill="#f3f3f9" />
        </svg>
      </div>
      <div className="relative w-full max-w-[440px] px-4 pt-14 pb-10">
        <div className="text-center mb-6">
          <div className="inline-flex items-center justify-center gap-2 bg-white rounded px-4 py-2 shadow">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/gora-logo.png" alt="Gora" className="h-8 w-auto" />
            <span className="text-[22px] font-bold tracking-wide text-[#405189]">GORA</span>
          </div>
          <p className="text-white/70 mt-4 text-[15px] font-medium">Zone Admin Panel</p>
        </div>
        <div className="bg-white rounded p-6 sm:p-8" style={{ boxShadow: '0 5px 10px rgba(30,32,37,.12)' }}>
          <div className="text-center mb-6">
            <h5 className="text-[16px] font-semibold text-[#405189]">Welcome Back !</h5>
            <p className="text-[13px] text-[#878a99] mt-1">Sign in to manage your zone.</p>
          </div>
          <form onSubmit={submit} className="space-y-4">
            <div>
              <label className="block text-[13px] font-medium text-[#495057] mb-2">Email</label>
              <input type="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="Enter email" className={field} />
            </div>
            <div>
              <label className="block text-[13px] font-medium text-[#495057] mb-2">Password</label>
              <input type="password" value={password} onChange={e => setPassword(e.target.value)} placeholder="Enter password" className={field} />
            </div>
            {error && <div className="bg-red-50 border border-red-200 text-red-600 text-sm px-4 py-3 rounded">{error}</div>}
            {info && <div className="bg-green-50 border border-green-200 text-green-700 text-sm px-4 py-3 rounded">{info}</div>}
            <div className="text-right -mt-1">
              <button type="button" className="text-[12.5px] text-[#405189]"
                onClick={async () => {
                  setError(''); setInfo('')
                  if (!email) { setError('Enter your email first, then tap “Forgot password?”'); return }
                  const r = await fetch('/api/zone-admin/forgot', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email }) })
                  const d = await r.json().catch(() => ({}))
                  setInfo(d.message || 'Request sent.')
                }}>Forgot password?</button>
            </div>
            <button type="submit" disabled={loading} className="w-full py-2.5 rounded text-white font-medium text-[14px] disabled:opacity-70"
              style={{ background: loading ? '#94a3b8' : '#0ab39c' }}>
              {loading ? 'Signing In...' : 'Sign In'}
            </button>
          </form>
        </div>
        <p className="text-center text-[#878a99] text-[13px] mt-8">&copy; {new Date().getFullYear()} Gora Cabs. All rights reserved.</p>
      </div>
    </div>
  )
}

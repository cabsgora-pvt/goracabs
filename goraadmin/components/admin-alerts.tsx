'use client'
import { useEffect, useState, useSyncExternalStore } from 'react'
import Link from 'next/link'
import { Siren, Volume2, VolumeX } from 'lucide-react'

// ─────────────────────────────────────────────────────────────────────────────
// One poll of GET /api/admin/alerts for the whole admin shell: the topbar bell,
// the sidebar badges and the SOS banner all read this store. Every 10 s while
// the tab is visible; paused when hidden, refreshed at once when shown again.
// ─────────────────────────────────────────────────────────────────────────────

export type AlertCounts = {
  sosActive: number; sosAcknowledged: number; ticketsOpen: number; driversPending: number
  withdrawalsPending: number; accountRequests: number; needsReview: number
}
export type AlertItem = { kind: string; id: string; at: string; href: string; text: string }
type State = { counts: AlertCounts | null; items: AlertItem[]; error: boolean }

const POLL_MS = 10_000
let state: State = { counts: null, items: [], error: false }
const listeners = new Set<() => void>()
let timer: ReturnType<typeof setInterval> | null = null
let inFlight = false

const emit = () => listeners.forEach(l => l())

export async function refreshAlerts() {
  if (inFlight || typeof document === 'undefined') return
  inFlight = true
  try {
    const r = await fetch('/api/admin/alerts', { cache: 'no-store' })
    if (r.ok) {
      const d = await r.json()
      state = { counts: d.counts || null, items: d.items || [], error: false }
    } else state = { ...state, error: true }
  } catch { state = { ...state, error: true } } finally { inFlight = false; emit() }
}

function start() {
  if (timer) return
  refreshAlerts()
  timer = setInterval(() => { if (document.visibilityState === 'visible') refreshAlerts() }, POLL_MS)
  document.addEventListener('visibilitychange', onVisible)
}
function stop() {
  if (timer) clearInterval(timer)
  timer = null
  document.removeEventListener('visibilitychange', onVisible)
}
function onVisible() { if (document.visibilityState === 'visible') refreshAlerts() }

function subscribe(l: () => void) {
  listeners.add(l)
  if (listeners.size === 1) start()
  return () => { listeners.delete(l); if (listeners.size === 0) stop() }
}
const serverSnap: State = { counts: null, items: [], error: false }

export function useAdminAlerts(): State {
  return useSyncExternalStore(subscribe, () => state, () => serverSnap)
}

// ── SOS banner + beep ──
const MUTE_KEY = 'gora-admin-sos-mute'

/** Red bar on every admin page while an SOS is waiting for acknowledgement.
 *  Beeps every poll while active — only after the admin has clicked or typed
 *  on the page (browsers refuse audio before a gesture), and not when muted. */
export function SosBanner() {
  const { counts } = useAdminAlerts()
  const active = counts?.sosActive || 0
  const [muted, setMuted] = useState(false)
  const [gesture, setGesture] = useState(false)

  useEffect(() => {
    try { setMuted(localStorage.getItem(MUTE_KEY) === '1') } catch {}
    const mark = () => setGesture(true)
    window.addEventListener('pointerdown', mark, { once: true })
    window.addEventListener('keydown', mark, { once: true })
    return () => { window.removeEventListener('pointerdown', mark); window.removeEventListener('keydown', mark) }
  }, [])

  useEffect(() => {
    if (!active || muted || !gesture || document.visibilityState !== 'visible') return
    beep()
  }, [active, muted, gesture, counts])

  if (!active) return null
  const toggleMute = () => {
    const m = !muted
    setMuted(m)
    try { localStorage.setItem(MUTE_KEY, m ? '1' : '0') } catch {}
  }
  return (
    <div role="alert" className="bg-red-600 text-white px-4 lg:px-6 py-2.5 flex items-center gap-3 text-sm" data-sos-banner="">
      <Siren className="w-5 h-5 animate-pulse flex-shrink-0" />
      <span className="font-semibold flex-1">
        {active} SOS alert{active === 1 ? '' : 's'} waiting — someone needs help now.
      </span>
      <button type="button" onClick={toggleMute} title={muted ? 'Unmute SOS sound' : 'Mute SOS sound'} aria-label={muted ? 'Unmute SOS sound' : 'Mute SOS sound'}
        className="p-1.5 rounded hover:bg-red-700">
        {muted ? <VolumeX className="w-4 h-4" /> : <Volume2 className="w-4 h-4" />}
      </button>
      <Link href="/support/sos" className="px-3 py-1 bg-white text-red-700 rounded font-semibold hover:bg-red-50">View SOS</Link>
    </div>
  )
}

let audioCtx: AudioContext | null = null
function beep() {
  try {
    const AC: typeof AudioContext | undefined = (window as any).AudioContext || (window as any).webkitAudioContext
    if (!AC) return
    audioCtx = audioCtx || new AC()
    const ctx = audioCtx
    if (ctx.state === 'suspended') ctx.resume().catch(() => {})
    const t = ctx.currentTime
    for (const [i, f] of [[0, 880], [1, 660]] as const) {
      const o = ctx.createOscillator(), g = ctx.createGain()
      o.type = 'square'; o.frequency.value = f
      g.gain.setValueAtTime(0.0001, t + i * 0.22)
      g.gain.exponentialRampToValueAtTime(0.15, t + i * 0.22 + 0.02)
      g.gain.exponentialRampToValueAtTime(0.0001, t + i * 0.22 + 0.2)
      o.connect(g).connect(ctx.destination)
      o.start(t + i * 0.22); o.stop(t + i * 0.22 + 0.21)
    }
  } catch { /* no audio: the banner still shows */ }
}

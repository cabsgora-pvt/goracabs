'use client'
import { useState } from 'react'
import { Modal } from '@/components/ui/modal'

// Admin actions on one ride, each behind a confirm dialog that shows the
// server's error. Money / destructive ones ask for the admin password through
// components/settings-password-guard (it wraps fetch). Used by the ride
// detail page, the Needs Review page and the scheduled rides page.
//
//   force_complete → POST /api/rides/{id}/force-complete
//   cancel         → POST /api/rides/{id}/admin { action: 'cancel', reason }
//   otp_unlock     → POST /api/rides/{id}/otp-unlock { which: 'both' }
//   verbal_confirm → POST /api/rides/{id}/otp-unlock { action: 'verbal_confirm', note }
//   resolve        → POST /api/rides/{id}/report-issue { action: 'resolve', note }

export type RideActionKind = 'force_complete' | 'cancel' | 'otp_unlock' | 'verbal_confirm' | 'resolve'

type Def = {
  label: string
  title: string
  detail: string
  btn: string
  note: 'none' | 'optional' | 'required'
  min?: number
  placeholder?: string
  call: (id: string, note: string) => Promise<Response>
  done: (d: any) => string
}

const post = (url: string, body: any) => fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
const ACTIVE = ['pending', 'accepted', 'arrived', 'ongoing']

export const ACTIONS: Record<RideActionKind, Def> = {
  force_complete: {
    label: 'Force complete', title: 'Force-complete this ride',
    detail: 'Ends the trip and settles it exactly as if the driver had ended it now: fare, commission and wallets move the normal way. An online ride is left waiting for the rider\'s payment.',
    btn: 'bg-blue-600 hover:bg-blue-700 text-white', note: 'optional', placeholder: 'Why (e.g. driver app crashed after the trip)',
    call: (id, note) => post(`/api/rides/${id}/force-complete`, { note }),
    done: d => d?.paymentStatus === 'pending' || d?.awaitingPayment ? 'Completed — waiting for the rider\'s online payment' : 'Ride completed and settled',
  },
  cancel: {
    label: 'Cancel ride', title: 'Cancel this ride',
    detail: 'Cancels as Gora support: no cancellation fee for the rider. Anything prepaid, split shares and wallet payments go back automatically; a prepaid ride already under way is flagged for a manual refund instead. Rider and driver are notified.',
    btn: 'bg-red-600 hover:bg-red-700 text-white', note: 'required', min: 3, placeholder: 'Reason (shown to the rider and driver)',
    call: (id, note) => post(`/api/rides/${id}/admin`, { action: 'cancel', reason: note }),
    done: d => d?.alreadyCancelled ? 'It was already cancelled' : `Ride cancelled${d?.refundedAmount > 0 ? ` · ₹${d.refundedAmount} refunded` : ''}${d?.refundReview ? ` · refund needs review (${String(d.refundReview).replace(/_/g, ' ')})` : ''}`,
  },
  otp_unlock: {
    label: 'Unlock OTP', title: 'Unlock the ride OTP',
    detail: 'Clears the wrong-code lock and issues a fresh OTP (and a fresh drop OTP for a parcel). The rider / receiver sees the new code in their app.',
    btn: 'bg-amber-500 hover:bg-amber-600 text-white', note: 'none',
    call: id => post(`/api/rides/${id}/otp-unlock`, { which: 'both' }),
    done: () => 'OTP unlocked — a new code was issued',
  },
  verbal_confirm: {
    label: 'Confirm delivery by phone', title: 'Confirm parcel handover by phone',
    detail: 'Marks the parcel delivered without the drop OTP, after you have confirmed with the receiver by phone. COD is recorded as collected. This is recorded with your name.',
    btn: 'bg-teal-600 hover:bg-teal-700 text-white', note: 'required', min: 5, placeholder: 'Who confirmed and how (e.g. receiver Ramesh on call 4:10 pm)',
    call: (id, note) => post(`/api/rides/${id}/otp-unlock`, { action: 'verbal_confirm', note }),
    done: () => 'Parcel marked delivered',
  },
  resolve: {
    label: 'Resolve review', title: 'Resolve the review flag',
    detail: 'Clears the "needs review" flag on this ride. It does not move any money.',
    btn: 'bg-green-600 hover:bg-green-700 text-white', note: 'optional', placeholder: 'Note (what you did)',
    call: (id, note) => post(`/api/rides/${id}/report-issue`, { action: 'resolve', note }),
    done: () => 'Review resolved',
  },
}

/** Which actions make sense for this ride right now. */
export function actionsFor(r: any, only?: RideActionKind[]): RideActionKind[] {
  const out: RideActionKind[] = []
  if (!r) return out
  const active = ACTIVE.includes(r.status)
  if (r.status === 'ongoing') out.push('force_complete')
  if (active) out.push('cancel')
  if (active && (r.otpLocked || r.dropOtpLocked)) out.push('otp_unlock')
  if (r.service === 'delivery' && r.status === 'ongoing' && ['collected', 'in_transit'].includes(r.deliveryPhase)) out.push('verbal_confirm')
  if (r.needsReview) out.push('resolve')
  return only ? out.filter(k => only.includes(k)) : out
}

export function RideActions({ ride, only, onDone, size = 'md' }: { ride: any; only?: RideActionKind[]; onDone?: (msg: string) => void; size?: 'sm' | 'md' }) {
  const [act, setAct] = useState<RideActionKind | null>(null)
  const kinds = actionsFor(ride, only)
  if (!kinds.length) return null
  const cls = size === 'sm' ? 'px-2.5 py-1 text-xs' : 'px-3 py-1.5 text-sm'
  return (
    <>
      <div className="flex flex-wrap gap-2">
        {kinds.map(k => (
          <button key={k} type="button" onClick={() => setAct(k)} className={`${cls} rounded-lg font-semibold whitespace-nowrap ${ACTIONS[k].btn}`}>{ACTIONS[k].label}</button>
        ))}
      </div>
      {act && <ConfirmRideAction kind={act} rideId={String(ride._id)} onClose={() => setAct(null)} onDone={m => { setAct(null); onDone?.(m) }} />}
    </>
  )
}

export function ConfirmRideAction({ kind, rideId, onClose, onDone }: { kind: RideActionKind; rideId: string; onClose: () => void; onDone: (msg: string) => void }) {
  const def = ACTIONS[kind]
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const tooShort = def.note === 'required' && note.trim().length < (def.min || 1)
  const run = async () => {
    setBusy(true); setErr('')
    try {
      const res = await def.call(rideId, note.trim())
      const d = await res.json().catch(() => ({}))
      if (res.ok) onDone(def.done(d))
      else setErr(d?.error || `Failed (${res.status})`)
    } catch (e: any) {
      setErr(e?.message || 'Failed')
    } finally { setBusy(false) }
  }
  return (
    <Modal title={def.title} onClose={() => !busy && onClose()} size="sm">
      <div className="space-y-4">
        <p className="text-sm text-gray-600">{def.detail}</p>
        {def.note !== 'none' && (
          <textarea value={note} onChange={e => setNote(e.target.value)} rows={3} maxLength={300} aria-label="Reason or note"
            placeholder={def.placeholder} className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm" />
        )}
        {err && <p role="alert" className="text-sm text-red-600 bg-red-50 border border-red-200 rounded-lg px-3 py-2">{err}</p>}
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} disabled={busy} className="px-4 py-2 border rounded-lg text-sm">Back</button>
          <button type="button" onClick={run} disabled={busy || tooShort} className={`px-4 py-2 rounded-lg text-sm font-semibold disabled:opacity-50 ${def.btn}`}>{busy ? 'Working…' : 'Confirm'}</button>
        </div>
      </div>
    </Modal>
  )
}

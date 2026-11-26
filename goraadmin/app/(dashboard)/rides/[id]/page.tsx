'use client'
import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { Header } from '@/components/header'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { RideActions } from '@/components/rides/ride-actions'
import { fmtIST, rupees, label, elapsed } from '@/components/rides/format'
import { ArrowLeft, User, Car, MapPin, AlertTriangle, MessageSquare, Wallet, Clock, Package, RotateCcw } from 'lucide-react'

// Admin ride detail: everything about one ride (GET /api/rides/{id}/admin),
// plus the admin actions (components/rides/ride-actions) and "Refund this
// ride" (POST /api/rides/{id}/admin { action: 'refund' }).

const card = 'bg-white rounded-xl border border-gray-100 shadow-sm'
const th = 'text-left text-xs font-semibold text-gray-500 uppercase tracking-wide px-4 py-2 whitespace-nowrap'
const td = 'px-4 py-2 align-top'
const has = (v: any) => v !== undefined && v !== null && v !== false && v !== '' && !(typeof v === 'number' && v === 0)

function Section({ title, icon: Icon, children, right }: any) {
  return (
    <div className={card}>
      <div className="px-5 py-3 border-b border-gray-100 flex items-center justify-between gap-2">
        <h3 className="font-semibold text-gray-800 flex items-center gap-2 text-sm">{Icon && <Icon className="w-4 h-4 text-gray-400" />}{title}</h3>
        {right}
      </div>
      <div className="p-5">{children}</div>
    </div>
  )
}

function KV({ rows }: { rows: [string, any, string?][] }) {
  const shown = rows.filter(([, v]) => has(v))
  if (!shown.length) return <p className="text-sm text-gray-400">—</p>
  return (
    <dl className="grid grid-cols-[minmax(120px,auto)_1fr] gap-x-4 gap-y-1.5 text-sm">
      {shown.map(([k, v, cls]) => (
        <div key={k} className="contents">
          <dt className="text-gray-500">{k}</dt>
          <dd className={`text-gray-800 break-words ${cls || ''}`}>{v}</dd>
        </div>
      ))}
    </dl>
  )
}

const Flag = ({ children, tone = 'red' }: any) => (
  <span className={`text-xs px-2 py-0.5 rounded-full font-semibold ${tone === 'red' ? 'bg-red-100 text-red-700' : tone === 'amber' ? 'bg-amber-100 text-amber-700' : 'bg-blue-100 text-blue-700'}`}>{children}</span>
)

export default function RideDetailPage({ params }: { params: { id: string } }) {
  const [d, setD] = useState<any>(null)
  const [err, setErr] = useState('')
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)
  const [refundOpen, setRefundOpen] = useState(false)

  const load = useCallback(() => {
    fetch(`/api/rides/${params.id}/admin`).then(async r => {
      const j = await r.json().catch(() => ({}))
      if (!r.ok) { setErr(j?.error || `Failed (${r.status})`); return }
      setErr(''); setD(j)
    }).catch(e => setErr(e?.message || 'Failed'))
  }, [params.id])
  useEffect(() => { load() }, [load])

  if (err && !d) return (
    <div><Header title="Ride" /><div className="p-6"><Link href="/rides" className="text-sm text-blue-600 hover:underline flex items-center gap-1"><ArrowLeft className="w-4 h-4" /> All rides</Link><p className="mt-6 text-red-600">{err}</p></div></div>
  )
  if (!d) return (
    <div><Header title="Ride" /><div className="flex items-center justify-center py-24"><div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" /></div></div>
  )

  const r = d.ride
  const rider = d.rider, driver = d.driver
  const refund = d.refund || {}
  const cancelled = r.status === 'cancelled'

  const timeline: [string, any, string?][] = ([
    ['Booked', r.createdAt],
    ['Scheduled for', r.scheduledAt],
    ['Departure', r.departureAt],
    ['Dispatch started', r.dispatchActivatedAt],
    ['Driver accepted', r.acceptedAt],
    ['Driver arrived', r.arrivedAt, r.arrivedFarKm ? `${r.arrivedFarKm} km from pickup by last fix` : r.arrivedUnverified ? 'location too old to check' : undefined],
    ['Trip started', r.startedAt],
    ['Rental started', r.rentalStartedAt],
    ['Hire started', r.hireStartedAt],
    ['Parcel collected', r.collectedAt],
    ['Parcel delivered', r.deliveredAt],
    ['Delivery failed', r.failedAt, r.failReason],
    ['Rental ended', r.rentalEndedAt],
    ['Completed', r.completedAt],
    ['Paid', r.paidAt],
    ['Cash collected (online → cash)', r.cashCollectedAt],
    ...(cancelled ? [[`Cancelled by ${r.cancelledBy || 'system'}`, r.updatedAt, [r.cancellationReason, r.cancelledFromStatus && `was ${r.cancelledFromStatus}`, '(time = last update)'].filter(Boolean).join(' · ')]] : []),
    ['Flagged for review', r.needsReviewAt, label(r.reviewReason)],
    ['Review resolved', r.reviewResolvedAt, [r.reviewResolvedBy, r.reviewNote].filter(Boolean).join(' · ')],
  ] as [string, any, string?][]).filter(([, t]) => !!t).sort((a, b) => new Date(a[1]).getTime() - new Date(b[1]).getTime())

  const stops: { kind: string; address: string; extra?: string }[] = [
    { kind: 'Pickup', address: r.pickupAddress, extra: r.pickupLat != null ? `${r.pickupLat}, ${r.pickupLng}` : undefined },
    ...(r.stops || []).map((s: any, i: number) => ({ kind: `Stop ${i + 1}`, address: s.address, extra: [s.done ? 'done' : '', s.waitMinutes ? `waited ${s.waitMinutes} min` : ''].filter(Boolean).join(' · ') })),
    ...(r.multiStops || []).map((s: any, i: number) => ({ kind: `Via ${i + 1}`, address: s.address })),
    ...(r.deliveryStops || []).map((s: any, i: number) => ({ kind: `Drop ${i + 1}`, address: s.address, extra: [s.receiverName, s.receiverPhone].filter(Boolean).join(' · ') })),
    ...(r.rentalStops || []).map((s: any, i: number) => ({ kind: `Rental stop ${i + 1}`, address: s.address, extra: s.at ? fmtIST(s.at) : undefined })),
    { kind: 'Drop', address: r.dropAddress, extra: r.dropLat != null ? `${r.dropLat}, ${r.dropLng}` : undefined },
  ].filter(s => s.address)

  const extTotal = (r.extensions || []).reduce((s: number, x: any) => s + (Number(x.amount) || 0), 0)
  const fb = r.fareBreakdown || {}
  const money: [string, any, string?][] = [
    ['Fare (booked)', has(r.fare) && rupees(r.fare)],
    ['Base / per km / per min', (fb.base || fb.perKm || fb.perMin) && `${rupees(fb.base)} · ${rupees(fb.perKm)}/km · ${rupees(fb.perMin)}/min${fb.surge ? ` · surge ${fb.surge}` : ''}`],
    ['Rental final fare', has(r.finalFare) && rupees(r.finalFare)],
    ['Rental extras', (r.extraHoursCharge || r.extraKmCharge) && `${rupees(r.extraHoursCharge)} hours + ${rupees(r.extraKmCharge)} km`],
    ['Hire final fare', has(r.hireFinalFare) && rupees(r.hireFinalFare)],
    ['Hire overtime', has(r.hireExtraCharge) && `${rupees(r.hireExtraCharge)} (${r.hireExtraHours || 0} h)`],
    ['Delivery final fare', has(r.deliveryFinalFare) && rupees(r.deliveryFinalFare)],
    ['Extensions', (r.extensions || []).length > 0 && `${(r.extensions || []).length} · ${rupees(extTotal)}`],
    ['Pending extension', r.pendingExtension && `${r.pendingExtension.hours} h · ${rupees(r.pendingExtension.amount)} (asked ${fmtIST(r.pendingExtension.requestedAt)})`],
    ['Waiting charge', has(r.waitingChargeTotal) && rupees(r.waitingChargeTotal)],
    ['Night halt / empty return', (r.nightHaltCharge || r.emptyReturnCharge) && `${rupees(r.nightHaltCharge)} / ${rupees(r.emptyReturnCharge)}`],
    ['Tip', has(r.tip) && rupees(r.tip)],
    ['Total fare', has(r.totalFare) && rupees(r.totalFare), 'font-semibold'],
    ['Tolls (paid to driver)', has(r.tollCharge) && `${rupees(r.tollCharge)} · ${(r.tolls || []).length} toll(s)${(r.tolls || []).some((t: any) => t.reportedAt) ? ' · reported by rider' : ''}`],
    ['Coupon', r.couponCode && `${r.couponCode} −${rupees(r.couponDiscount)}${r.couponSource ? ` (${r.couponSource})` : ''}${r.couponReleasedAt ? ' · given back' : ''}`],
    ['Coupon reimbursed to driver', has(r.couponReimbursed) && rupees(r.couponReimbursed)],
    ['Commission', has(r.commissionAmount) && `${rupees(r.commissionAmount)}${r.commissionPercent != null ? ` (${r.commissionPercent}%)` : ''}`],
    ['Franchise share', r.franchiseShare?.amount > 0 && `${rupees(r.franchiseShare.amount)} (${r.franchiseShare.percent}%)`],
    ['Driver earning', has(r.driverEarning) && rupees(r.driverEarning)],
    ['Payment', `${r.paymentMode || '—'} · ${r.paymentStatus || '—'}${r.paymentSwitchedToCash ? ' · switched to cash (wallet short)' : ''}${r.awaitingPayment ? ' · awaiting payment' : ''}`],
    ['Amount due', has(r.amountDue) && rupees(r.amountDue)],
    ['Rider wallet debit', has(r.riderWalletDebit) && rupees(r.riderWalletDebit)],
    ['Online payment', r.onlinePayment && `${rupees(r.onlinePayment.amount)} · ${r.onlinePayment.paymentId}${r.onlinePayment.settled ? ' · settled' : ' · held'}`],
    ['Pending (online) driver earning / commission', (r.pendingDriverEarning || r.pendingCommission) && `${rupees(r.pendingDriverEarning)} / ${rupees(r.pendingCommission)}`],
    ['Prepaid', (r.prepaidAmount > 0 || r.prepaidUnlinked) && `${rupees(r.prepaidAmount)} via ${r.prepaidVia || '?'}${r.prepaidRef ? ` · ${r.prepaidRef}` : ''}${r.prepaidUnlinked ? ' · NOT LINKED' : ''}`, r.prepaidUnlinked ? 'text-red-600 font-semibold' : ''],
    ['Prepay captured / excess refunded', (r.prepaidCaptured || r.prepaidExcessRefunded) && `${rupees(r.prepaidCaptured)} / ${rupees(r.prepaidExcessRefunded)}`],
    ['Prepaid shortfall', r.prepaidShortfall && 'yes — rider still owes the amount due', 'text-orange-600'],
    ['Split shares', (r.splitRequests || []).length > 0 && (r.splitRequests || []).map((s: any) => `${s.name || s.phone} ${rupees(s.share)} ${s.status}${s.reversedAt ? ' (reversed)' : ''}`).join(' · ')],
    ['Split collected / commission', (r.splitCollected || r.splitCommission) && `${rupees(r.splitCollected)} / ${rupees(r.splitCommission)}`],
    ['Cancellation fee', has(r.cancellationFee) && rupees(r.cancellationFee)],
    ['Cancellation fee (not collected)', has(r.cancellationFeeUncollected) && rupees(r.cancellationFeeUncollected)],
    ['Auto refunds', (r.refundedAmount > 0 || r.refundPending) && `${rupees(r.refundedAmount)}${r.refundPending ? ' · pending' : ''}`],
    ['Admin refunds', has(r.adminRefundTotal) && rupees(r.adminRefundTotal)],
    ['Refund review', r.refundReview && `${label(r.refundReview)}${r.refundReviewResolvedAt ? ` · handled by ${r.refundReviewResolvedBy} ${fmtIST(r.refundReviewResolvedAt)}` : ''}`, r.refundReviewResolvedAt ? '' : 'text-red-600 font-semibold'],
    ['COD amount / collected', (r.codAmount || r.codCollected) && `${rupees(r.codAmount)} / ${rupees(r.codCollected)}`],
    ['COD to sender / still owed', (r.codSenderCredited != null || r.codPendingRemittance) && `${rupees(r.codSenderCredited)} / ${rupees(r.codPendingRemittance)}`, r.codPendingRemittance > 0 && !r.codRemittedAt ? 'text-red-600 font-semibold' : ''],
    ['COD remitted by hand', r.codRemittedAt && `${fmtIST(r.codRemittedAt)} by ${r.codRemittedBy}${r.codRemittedNote ? ` · ${r.codRemittedNote}` : ''}`],
  ]

  const photos: [string, string][] = ([
    ['Proof of delivery', r.deliveryProofPhoto], ['Receiver signature', r.deliverySignature], ['Failed delivery', r.deliveryFailPhoto],
    ...(r.parcelPhotos || []).map((p: string, i: number) => [`Parcel photo ${i + 1}`, p]),
  ] as [string, string][]).filter(([, u]) => !!u)

  return (
    <div>
      <Header title="Ride details" />
      <div className="p-6 space-y-5">
        <Link href="/rides" className="text-sm text-blue-600 hover:underline inline-flex items-center gap-1"><ArrowLeft className="w-4 h-4" /> All rides</Link>

        {/* Header */}
        <div className={`${card} p-5 space-y-3`}>
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="space-y-1">
              <div className="flex flex-wrap items-center gap-2">
                <h2 className="text-lg font-bold text-gray-900 capitalize">{label(r.service || 'taxi')}{r.vehicleType ? ` · ${r.vehicleType}` : ''}{r.tripType && r.service === 'outstation' ? ` · ${label(r.tripType)}` : ''}</h2>
                <Badge status={r.status} />
                {r.needsReview && <Flag>Needs review: {label(r.reviewReason)}</Flag>}
                {r.stuckSince && <Flag tone="amber">Stuck since {fmtIST(r.stuckSince)}</Flag>}
                {r.kmAnomaly && <Flag>km anomaly</Flag>}
                {(r.otpLocked || r.dropOtpLocked) && <Flag tone="amber">{r.dropOtpLocked ? 'Drop OTP locked' : 'OTP locked'}</Flag>}
                {r.awaitingPayment && <Flag tone="blue">Awaiting payment</Flag>}
                {r.refundReview && !r.refundReviewResolvedAt && <Flag>Refund review: {label(r.refundReview)}</Flag>}
              </div>
              <p className="text-xs text-gray-500 font-mono">Ride {r._id}</p>
              <p className="text-xs text-gray-500">
                Zone: {d.zone?.name || (r.zoneId ? String(r.zoneId) : '—')} · Booked {fmtIST(r.createdAt)}
                {r.rentalPhase && r.service === 'rental' ? ` · phase ${label(r.rentalPhase)}` : ''}
                {r.hirePhase && r.service === 'hire_driver' ? ` · phase ${label(r.hirePhase)}` : ''}
                {r.deliveryPhase && r.service === 'delivery' ? ` · phase ${label(r.deliveryPhase)}` : ''}
                {r.outstationPhase && r.service === 'outstation' ? ` · phase ${label(r.outstationPhase)}` : ''}
              </p>
            </div>
            <div className="flex flex-wrap gap-2 items-start">
              <RideActions ride={r} onDone={m => { setToast({ msg: m, type: 'success' }); load() }} />
              <button type="button" onClick={() => setRefundOpen(true)} disabled={!!refund.blocked || !(refund.refundable > 0)}
                title={refund.blocked || (!(refund.refundable > 0) ? 'Nothing left to refund' : '')}
                className="px-3 py-1.5 text-sm rounded-lg font-semibold bg-purple-600 hover:bg-purple-700 text-white disabled:opacity-40 inline-flex items-center gap-1">
                <RotateCcw className="w-4 h-4" /> Refund this ride
              </button>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 xl:grid-cols-3 gap-5">
          <div className="xl:col-span-2 space-y-5">
            <Section title="Timeline" icon={Clock}>
              <ol className="relative border-l border-gray-200 ml-2 space-y-3">
                {timeline.map(([k, t, extra], i) => (
                  <li key={i} className="ml-4">
                    <div className="absolute -left-1.5 mt-1.5 w-3 h-3 rounded-full bg-blue-500 border-2 border-white" />
                    <p className="text-sm text-gray-800 font-medium">{k} <span className="text-gray-500 font-normal">· {fmtIST(t, true)}</span></p>
                    {extra && <p className="text-xs text-gray-500">{extra}</p>}
                  </li>
                ))}
              </ol>
              {r.startedAt && <p className="mt-3 text-xs text-gray-500">Trip time: {elapsed(r.startedAt, r.completedAt || (r.status === 'ongoing' ? Date.now() : r.updatedAt))}{r.acceptedAt && r.arrivedAt ? ` · pickup took ${elapsed(r.acceptedAt, r.arrivedAt)}${r.predictedEtaMin != null ? ` (promised ${r.predictedEtaMin} min)` : ''}` : ''}</p>}
            </Section>

            <Section title="Route" icon={MapPin}>
              <ol className="space-y-2 text-sm">
                {stops.map((s, i) => (
                  <li key={i} className="flex gap-3">
                    <span className={`text-xs font-semibold w-24 flex-shrink-0 ${s.kind === 'Pickup' ? 'text-green-600' : s.kind === 'Drop' ? 'text-red-600' : 'text-orange-600'}`}>{s.kind}</span>
                    <span className="text-gray-800">{s.address}{s.extra && <span className="block text-xs text-gray-400">{s.extra}</span>}</span>
                  </li>
                ))}
              </ol>
              <div className="mt-4">
                <KV rows={[
                  ['Cities', (r.cityFrom || r.cityTo) && `${r.cityFrom || '?'} → ${r.cityTo || '?'}`],
                  ['Road distance / time', (r.distance || r.duration) && `${r.distance ?? '—'} km · ${r.duration ?? '—'} min`],
                  ['Tracked distance', has(r.actualDistance) && `${r.actualDistance} km`],
                  ['Ended away from drop', has(r.endedAwayKm) && `${r.endedAwayKm} km`, 'text-red-600 font-semibold'],
                  ['Rental package', (r.packageHours || r.packageKm) && `${r.packageHours} h / ${r.packageKm} km · extra ${rupees(r.extraHourRate)}/h, ${rupees(r.extraKmRate)}/km`],
                  ['Rental used', r.service === 'rental' && `${(r.actualHours || 0).toFixed(2)} h / ${(r.actualKm || 0).toFixed(1)} km`],
                  ['Rental km expected', has(r.kmExpected) && `${r.kmExpected} km (actual ${(r.actualKm || 0).toFixed(1)} km)${r.kmAnomaly ? ' — over 1.5× expected' : ''}`, r.kmAnomaly ? 'text-red-600 font-semibold' : ''],
                  ['Hire', r.service === 'hire_driver' && `${r.hireTotalHours || 0} h booked · ${(r.hireActualHours || 0).toFixed(2)} h worked · ${rupees(r.hirePerHour)}/h · ${r.transmission || '—'}`],
                  ['Passengers', r.numPassengers > 1 && r.numPassengers],
                  ['Preferences', [(r.preferFemaleDriver ? 'female driver' : ''), ...(r.preferences || [])].filter(Boolean).join(', ')],
                ]} />
              </div>
            </Section>

            <Section title="Money" icon={Wallet}>
              <KV rows={money} />
            </Section>

            <Section title="Refund" icon={RotateCcw}
              right={<span className="text-sm">Refundable now: <b className={refund.refundable > 0 ? 'text-purple-700' : 'text-gray-500'}>{rupees(refund.refundable)}</b></span>}>
              <div className="space-y-3 text-sm">
                <p className="text-gray-600">Rider paid for this ride: <b>{rupees(refund.paid)}</b>{(refund.parts || []).length > 0 && <span className="text-gray-500"> ({refund.parts.map((p: any) => `${p.label} ${rupees(p.amount)}`).join(' + ')})</span>} · already refunded to the rider: <b>{rupees(refund.refunded)}</b></p>
                {refund.blocked && <p className="text-amber-700 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2">{refund.blocked}</p>}
                <p className="text-xs text-gray-500">Automatic refunds (cancel, no driver found, unusable online payment) are counted first; an admin refund can only give back what is left, never more than the rider paid. Split shares paid by co-riders are not included. Gora pays the refund — the driver&apos;s wallet is not changed.</p>
                {(refund.refunds || []).length > 0 && (
                  <table className="w-full text-sm"><thead className="bg-gray-50"><tr>{['When', 'Amount', 'Note', 'Ref'].map(h => <th key={h} className={th}>{h}</th>)}</tr></thead>
                    <tbody className="divide-y divide-gray-50">{refund.refunds.map((x: any) => (
                      <tr key={x.ref}><td className={`${td} text-xs whitespace-nowrap`}>{fmtIST(x.at)}</td><td className={`${td} font-semibold`}>{rupees(x.amount)}</td><td className={`${td} text-xs`}>{x.note}</td><td className={`${td} text-xs font-mono text-gray-500 break-all`}>{x.ref}</td></tr>
                    ))}</tbody></table>
                )}
              </div>
            </Section>

            {(d.walletTx?.length > 0 || d.driverTx?.length > 0) && (
              <Section title="Ledger rows for this ride" icon={Wallet}>
                <div className="space-y-4">
                  {d.walletTx?.length > 0 && (
                    <div className="overflow-x-auto"><p className="text-xs font-semibold text-gray-500 mb-1">Rider wallet</p>
                      <table className="w-full text-sm"><thead className="bg-gray-50"><tr>{['When', 'Type', 'Amount', 'Source', 'Note', 'Balance after'].map(h => <th key={h} className={th}>{h}</th>)}</tr></thead>
                        <tbody className="divide-y divide-gray-50">{d.walletTx.map((t: any) => (
                          <tr key={t._id}><td className={`${td} text-xs whitespace-nowrap`}>{fmtIST(t.createdAt)}</td><td className={`${td} capitalize ${t.type === 'credit' ? 'text-green-700' : 'text-red-700'}`}>{t.type}</td><td className={`${td} font-semibold`}>{rupees(t.amount)}</td><td className={td}>{t.source}</td><td className={`${td} text-xs`}>{t.note}</td><td className={td}>{rupees(t.balanceAfter)}</td></tr>
                        ))}</tbody></table></div>
                  )}
                  {d.driverTx?.length > 0 && (
                    <div className="overflow-x-auto"><p className="text-xs font-semibold text-gray-500 mb-1">Driver ledger</p>
                      <table className="w-full text-sm"><thead className="bg-gray-50"><tr>{['When', 'Type', 'Amount', 'Mode', 'Description', 'Balance after'].map(h => <th key={h} className={th}>{h}</th>)}</tr></thead>
                        <tbody className="divide-y divide-gray-50">{d.driverTx.map((t: any) => (
                          <tr key={t._id}><td className={`${td} text-xs whitespace-nowrap`}>{fmtIST(t.createdAt)}</td><td className={td}>{label(t.type)}</td><td className={`${td} font-semibold ${t.amount < 0 ? 'text-red-700' : 'text-green-700'}`}>{rupees(t.amount)}</td><td className={td}>{t.paymentMode}</td><td className={`${td} text-xs`}>{t.description}</td><td className={td}>{t.balanceAfter != null ? rupees(t.balanceAfter) : '—'}</td></tr>
                        ))}</tbody></table></div>
                  )}
                </div>
              </Section>
            )}

            {r.service === 'delivery' && (
              <Section title="Parcel" icon={Package}>
                <KV rows={[
                  ['Sender', [r.senderName, r.senderPhone].filter(Boolean).join(' · ')],
                  ['Receiver', [r.receiverName, r.receiverPhone].filter(Boolean).join(' · ')],
                  ['Item', [r.itemType, r.weightKg ? `${r.weightKg} kg` : '', r.packageSize, r.isFragile ? 'fragile' : '', r.itemValue ? `value ${rupees(r.itemValue)}` : ''].filter(Boolean).join(' · ')],
                  ['Phase', label(r.deliveryPhase)],
                  ['Delivered distance', has(r.deliveryDistance) && `${r.deliveryDistance} km`],
                  ['Confirmed by phone', r.deliveryVerbalConfirm && `${r.deliveryVerbalConfirm.by} · ${fmtIST(r.deliveryVerbalConfirm.at)} · “${r.deliveryVerbalConfirm.note}”`, 'text-teal-700'],
                ]} />
                {photos.length > 0 && (
                  <div className="mt-4 grid grid-cols-2 sm:grid-cols-4 gap-3">
                    {photos.map(([k, u]) => (
                      <a key={k + u} href={u} target="_blank" rel="noreferrer" className="block">
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img src={u} alt={k} className="w-full h-32 object-cover rounded-lg border" />
                        <span className="text-xs text-gray-500">{k}</span>
                      </a>
                    ))}
                  </div>
                )}
              </Section>
            )}

            <Section title={`Chat (${(r.messages || []).length})`} icon={MessageSquare}>
              {(r.messages || []).length === 0 ? <p className="text-sm text-gray-400">No messages</p> : (
                <div className="space-y-2 max-h-96 overflow-y-auto">
                  {r.messages.map((m: any, i: number) => (
                    <div key={m._id || i} className={`flex ${m.sender === 'driver' ? 'justify-end' : 'justify-start'}`}>
                      <div className={`max-w-[75%] rounded-xl px-3 py-2 text-sm ${m.sender === 'driver' ? 'bg-blue-50 text-blue-900' : 'bg-gray-100 text-gray-800'}`}>
                        <p className="text-[11px] font-semibold opacity-70 capitalize">{m.sender === 'user' ? 'rider' : m.sender} · {fmtIST(m.createdAt)}</p>
                        <p className="whitespace-pre-wrap break-words">{m.text}</p>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </Section>
          </div>

          <div className="space-y-5">
            <Section title="Rider" icon={User} right={r.riderId && <Link href={`/users/${r.riderId}`} className="text-xs text-blue-600 hover:underline">Open profile</Link>}>
              <KV rows={[
                ['Name', rider?.name || r.riderName],
                ['Phone', rider?.phone || r.riderPhone],
                ['Wallet', rider && rupees(rider.walletBalance)],
                ['Account', rider?.status],
                ['Rated driver', has(r.driverRating) && `${r.driverRating}★${r.riderReview ? ` “${r.riderReview}”` : ''}`],
              ]} />
              {!rider && r.riderId && <p className="text-xs text-red-600 mt-2">Account no longer exists</p>}
            </Section>
            <Section title="Driver" icon={Car} right={r.driverId && <Link href={`/drivers/${r.driverId}`} className="text-xs text-blue-600 hover:underline">Open profile</Link>}>
              {!r.driverId ? <p className="text-sm text-gray-400">No driver assigned</p> : (
                <KV rows={[
                  ['Name', driver?.name || r.driverName],
                  ['Phone', driver?.phone || r.driverPhone],
                  ['Vehicle', driver && [driver.selectedVehicleTypeName, driver.vehicleModel, driver.vehicleNumber || driver.vehicleRegistrationNumber].filter(Boolean).join(' · ')],
                  ['Rating', driver?.rating != null && `${driver.rating}★ · ${driver.totalRides || 0} rides`],
                  ['Wallet', driver && rupees(driver.walletBalance)],
                  ['Online', driver && (driver.isOnline ? 'yes' : 'no')],
                  ['Last location', driver?.locationUpdatedAt && `${fmtIST(driver.locationUpdatedAt)} (${elapsed(driver.locationUpdatedAt)} ago)`],
                  ['Rated rider', has(r.riderRating) && `${r.riderRating}★${r.driverReview ? ` “${r.driverReview}”` : ''}`],
                ]} />
              )}
            </Section>

            <Section title="Review & issues" icon={AlertTriangle}>
              <KV rows={[
                ['Needs review', r.needsReview ? `yes — ${label(r.reviewReason)}` : r.reviewResolvedAt ? 'resolved' : 'no', r.needsReview ? 'text-red-600 font-semibold' : ''],
                ['Flagged at', r.needsReviewAt && fmtIST(r.needsReviewAt)],
                ['Stuck since', r.stuckSince && fmtIST(r.stuckSince), 'text-orange-600'],
                ['Resolved', r.reviewResolvedAt && `${fmtIST(r.reviewResolvedAt)} by ${r.reviewResolvedBy}${r.reviewNote ? ` · ${r.reviewNote}` : ''}`],
                ['No driver flagged', r.noDriverFlaggedAt && fmtIST(r.noDriverFlaggedAt)],
                ['OTP attempts', (r.otpAttempts || r.dropOtpAttempts) && `${r.otpAttempts || 0} pickup · ${r.dropOtpAttempts || 0} drop`],
                ['Offer round', has(r.offerRound) && r.offerRound],
              ]} />
              {(r.issueReports || []).length > 0 && (
                <ul className="mt-3 space-y-2">
                  {r.issueReports.map((x: any, i: number) => (
                    <li key={i} className="text-sm border border-red-100 bg-red-50/50 rounded-lg px-3 py-2">
                      <span className="font-medium capitalize">{label(x.kind)}</span> <span className="text-xs text-gray-500">by {x.by} · {fmtIST(x.at)}</span>
                      {x.note && <p className="text-xs text-gray-700 italic">“{x.note}”</p>}
                    </li>
                  ))}
                </ul>
              )}
            </Section>

            {(d.audit || []).length > 0 && (
              <Section title="Admin actions" icon={User}>
                <ul className="space-y-2 text-sm">
                  {d.audit.map((a: any) => (
                    <li key={a._id}><span className="font-medium">{a.action}</span> <span className="text-xs text-gray-500">· {a.email} · {fmtIST(a.at)}</span>{a.summary && <p className="text-xs text-gray-600">{a.summary}</p>}</li>
                  ))}
                </ul>
              </Section>
            )}
          </div>
        </div>
      </div>

      {refundOpen && <RefundDialog rideId={r._id} refund={refund} onClose={() => setRefundOpen(false)}
        onDone={m => { setRefundOpen(false); setToast({ msg: m, type: 'success' }); load() }} />}
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}

function newKey() {
  try { return (crypto as any).randomUUID().replace(/-/g, '') } catch { return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 12)}` }
}

function RefundDialog({ rideId, refund, onClose, onDone }: { rideId: string; refund: any; onClose: () => void; onDone: (m: string) => void }) {
  const [amount, setAmount] = useState(String(refund.refundable || ''))
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  // One key per dialog: a retry / double click of this same request can
  // never credit twice. A new dialog is a new refund.
  const [key] = useState(newKey)
  const n = Number(amount)
  const bad = !(n > 0) || n > (refund.refundable || 0) + 0.001 || reason.trim().length < 5
  const run = async () => {
    setBusy(true); setErr('')
    try {
      const res = await fetch(`/api/rides/${rideId}/admin`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'refund', amount: Math.round(n * 100) / 100, reason: reason.trim(), key }),
      })
      const d = await res.json().catch(() => ({}))
      if (res.ok) onDone(d.duplicate ? 'This refund was already made — nothing more credited' : `Refunded ${rupees(d.amount)} to the rider's wallet`)
      else setErr(d?.error || `Failed (${res.status})`)
    } catch (e: any) { setErr(e?.message || 'Failed') } finally { setBusy(false) }
  }
  return (
    <Modal title="Refund this ride" onClose={() => !busy && onClose()} size="sm">
      <div className="space-y-3">
        <p className="text-sm text-gray-600">Credits the rider&apos;s Gora wallet. At most <b>{rupees(refund.refundable)}</b>: they paid {rupees(refund.paid)} for this ride and {rupees(refund.refunded)} was already refunded. The driver is not charged.</p>
        <label className="block text-sm">
          <span className="text-gray-600">Amount (₹)</span>
          <input type="number" min={0} step="0.01" max={refund.refundable} value={amount} onChange={e => setAmount(e.target.value)} aria-label="Refund amount"
            className="mt-1 w-full border border-gray-300 rounded-lg px-3 py-2 text-sm" />
        </label>
        <textarea value={reason} onChange={e => setReason(e.target.value)} rows={3} maxLength={300} aria-label="Refund reason"
          placeholder="Reason (required — the rider sees it in their wallet)" className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm" />
        {err && <p role="alert" className="text-sm text-red-600 bg-red-50 border border-red-200 rounded-lg px-3 py-2">{err}</p>}
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} disabled={busy} className="px-4 py-2 border rounded-lg text-sm">Back</button>
          <button type="button" onClick={run} disabled={busy || bad} className="px-4 py-2 bg-purple-600 text-white rounded-lg text-sm font-semibold disabled:opacity-50">{busy ? 'Refunding…' : `Refund ${n > 0 ? rupees(n) : ''}`}</button>
        </div>
      </div>
    </Modal>
  )
}

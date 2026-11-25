import { connectDB } from '@/lib/mongodb'
import Settings from '@/models/Settings'
import SOSContact from '@/models/SOSContact'
import Ride from '@/models/Ride'
import SosEscalation from '@/models/SosEscalation'
import { sendSms } from '@/lib/sms'

// ─────────────────────────────────────────────────────────────────────────────
// SOS escalation. Call after an SOS alert is stored (POST /api/support/sos-alert):
//     escalateSos(alert).catch(() => {})      // don't await: never delay the SOS
// Texts settings.support.opsPhones (comma list) and the person's own emergency
// contacts (SOSContact with ownerId = rider/driver id) with who raised it, the
// ride and a map link. Every attempt is logged to SosEscalation.
//
// Outside production nothing is sent — the attempt is logged as stubbed — so a
// local test can never text a real number. Production with no SMS provider
// configured logs the provider's "not configured" result.
// ─────────────────────────────────────────────────────────────────────────────

export type SosAlertLike = {
  _id?: any; rideId?: any; triggeredBy?: 'user' | 'driver' | string
  name?: string; phone?: string; lat?: number; lng?: number; address?: string
}

const MAX_RECIPIENTS = 10

function phones(list: unknown): string[] {
  return String(list || '').split(/[,;\s]+/).map(p => p.replace(/\D/g, '').slice(-10)).filter(p => p.length === 10)
}

export function sosMessage(a: SosAlertLike, ride: any): string {
  const who = a.triggeredBy === 'driver' ? 'Driver' : 'Rider'
  const where = typeof a.lat === 'number' && typeof a.lng === 'number' ? ` https://maps.google.com/?q=${a.lat},${a.lng}` : ''
  const rideTxt = ride?.rideNumber || ride?._id ? ` Ride ${ride.rideNumber || String(ride._id).slice(-6)}.` : ''
  return `GORA SOS: ${who} ${a.name || ''} (${a.phone || 'no phone'}) needs help.${rideTxt}${a.address ? ' ' + String(a.address).slice(0, 80) : ''}${where}`.slice(0, 300)
}

export async function escalateSos(alert: SosAlertLike, opts: { personId?: string } = {}) {
  await connectDB()
  const s: any = await Settings.findOne({ key: 'global' }).select('support').lean()
  const ride: any = alert.rideId ? await Ride.findById(alert.rideId).select('riderId driverId rideNumber').lean().catch(() => null) : null
  const personId = opts.personId || (ride ? String(alert.triggeredBy === 'driver' ? ride.driverId || '' : ride.riderId || '') : '')
  const contacts: any[] = personId
    ? await SOSContact.find({ ownerId: personId, isActive: true }).select('phone').limit(MAX_RECIPIENTS).lean()
    : []

  const seen = new Set<string>()
  const to: { phone: string; kind: 'ops' | 'contact' }[] = []
  for (const p of phones(s?.support?.opsPhones)) if (!seen.has(p)) { seen.add(p); to.push({ phone: p, kind: 'ops' }) }
  for (const c of contacts) for (const p of phones(c.phone)) if (!seen.has(p)) { seen.add(p); to.push({ phone: p, kind: 'contact' }) }
  const recipients = to.slice(0, MAX_RECIPIENTS)

  const msg = sosMessage(alert, ride)
  const stubbed = process.env.NODE_ENV !== 'production'
  const results = []
  for (const r of recipients) {
    if (stubbed) { results.push({ ...r, ok: false, result: 'stubbed (not production)' }); continue }
    const out = await sendSms(r.phone, msg).catch((e: any) => ({ success: false, message: e?.message || 'failed' }))
    results.push({ ...r, ok: !!out.success, result: String(out.message || '').slice(0, 200) })
  }
  await SosEscalation.create({ alertId: alert._id, rideId: alert.rideId || undefined, recipients: results, stubbed }).catch(() => {})
  return { sent: results.filter(r => r.ok).length, recipients: results, stubbed }
}

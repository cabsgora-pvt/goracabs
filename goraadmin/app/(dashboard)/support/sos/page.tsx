'use client'
import { useState, useEffect } from 'react'
import Link from 'next/link'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import { Pager } from '@/components/ui/pager'
import { refreshAlerts } from '@/components/admin-alerts'
import { Plus, Trash2, Phone, AlertCircle, CheckCircle, Eye } from 'lucide-react'

const SOS_FILTERS = [
  { v: 'open', label: 'Unresolved' }, { v: 'active', label: 'Active' },
  { v: 'acknowledged', label: 'Acknowledged' }, { v: 'resolved', label: 'Resolved' }, { v: '', label: 'All' },
]
const SOS_LIMIT = 50
const fmt = (d?: string) => d ? new Date(d).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', dateStyle: 'medium', timeStyle: 'short' }) : ''

export default function SOSPage() {
  const [contacts, setContacts] = useState<any[]>([])
  const [alerts, setAlerts] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  // Alerts: unresolved first (active, then acknowledged), newest first (server order).
  const [sosFilter, setSosFilter] = useState('open')
  const [sosPage, setSosPage] = useState(1)
  const [sosTotal, setSosTotal] = useState(0)
  const [sosCounts, setSosCounts] = useState<Record<string, number>>({})
  const [resolving, setResolving] = useState<any | null>(null)
  const [resolveNote, setResolveNote] = useState('')
  const [deleting, setDeleting] = useState<any | null>(null)
  const [showModal, setShowModal] = useState(false)
  const [form, setForm] = useState({ name: '', phone: '', relation: '' })
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const fetchAlerts = () => {
    const p = new URLSearchParams({ page: String(sosPage), limit: String(SOS_LIMIT) })
    if (sosFilter) p.set('status', sosFilter)
    fetch(`/api/support/sos-alert?${p}`)
      .then(r => r.json())
      .then(d => { setAlerts(d.alerts || []); setSosTotal(d.total || 0); setSosCounts(d.counts || {}) })
      .catch(() => {})
  }

  const fetchContacts = () => {
    fetch('/api/support/sos')
      .then(r => r.json())
      .then(d => { setContacts(d.contacts || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchContacts() }, [])
  useEffect(() => {
    fetchAlerts()
    const t = setInterval(() => { if (document.visibilityState === 'visible') fetchAlerts() }, 10000) // live alerts every 10s
    return () => clearInterval(t)
  }, [sosFilter, sosPage]) // eslint-disable-line react-hooks/exhaustive-deps

  const actOnAlert = async (id: string, action: 'acknowledge' | 'resolve', note?: string) => {
    const res = await fetch('/api/support/sos-alert', {
      method: 'PATCH', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, action, note }),
    })
    const d = await res.json().catch(() => ({}))
    if (!res.ok) { setToast({ msg: d.error || 'Could not update the alert', type: 'error' }); throw new Error(d.error || 'failed') }
    setToast({ msg: d.unchanged ? 'Already handled — list refreshed' : action === 'resolve' ? 'SOS resolved' : 'SOS acknowledged', type: 'success' })
    fetchAlerts(); refreshAlerts()
  }

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault()
    const res = await fetch('/api/support/sos', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...form, addedBy: 'admin', isActive: true }),
    })
    if (res.ok) {
      fetchContacts()
      setShowModal(false)
      setForm({ name: '', phone: '', relation: '' })
      setToast({ msg: 'SOS contact added', type: 'success' })
    }
  }

  const deleteContact = async (id: string) => {
    const res = await fetch(`/api/support/sos/${id}`, { method: 'DELETE' })
    if (res.ok) { fetchContacts(); setDeleting(null); setToast({ msg: 'Contact removed', type: 'success' }) }
    else setToast({ msg: 'Could not remove the contact', type: 'error' })
  }

  return (
    <div>
      <Header title="SOS Alerts & Contacts" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="SOS Alerts & Emergency Contacts"
          subtitle="Handle live SOS alerts and manage the emergency contacts shown to users during rides"
          action={
            <button type="button" onClick={() => setShowModal(true)}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-lg text-sm font-medium hover:bg-primary-dark">
              <Plus className="w-4 h-4" /> Add SOS Contact
            </button>
          }
        />

        {/* Live SOS alerts raised during rides */}
        <div className="bg-white rounded-xl border border-gray-100 shadow-sm">
          <div className="px-5 py-3 border-b border-gray-100 flex items-center gap-2">
            <AlertCircle className="w-5 h-5 text-red-600" />
            <h3 className="font-semibold text-gray-800">Live SOS Alerts</h3>
            {(sosCounts.active || 0) > 0 && (
              <span className="text-xs px-2 py-0.5 bg-red-600 text-white rounded-full animate-pulse">
                {sosCounts.active} active
              </span>
            )}
            <span className="ml-auto text-xs text-gray-400">auto-refreshes every 10s</span>
          </div>
          <div className="px-5 py-3 border-b border-gray-100 flex flex-wrap gap-2" aria-label="SOS status filter">
            {SOS_FILTERS.map(f => {
              const n = f.v === 'open' ? (sosCounts.active || 0) + (sosCounts.acknowledged || 0) : f.v ? (sosCounts[f.v] || 0) : undefined
              return (
                <button key={f.v || 'all'} type="button" onClick={() => { setSosFilter(f.v); setSosPage(1) }}
                  className={`px-3 py-1 rounded-full text-xs font-medium border ${sosFilter === f.v ? 'bg-primary text-white border-primary' : 'bg-white text-gray-600 border-gray-200 hover:bg-gray-50'}`}>
                  {f.label}{n !== undefined ? ` (${n})` : ''}
                </button>
              )
            })}
          </div>
          {alerts.length === 0 ? (
            <p className="px-5 py-6 text-sm text-gray-400">No SOS alerts here.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-100">
                    {['When', 'Status', 'By', 'Name', 'Phone', 'Ride', 'Location', 'Actions'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {alerts.map(a => {
                    const ride = a.rideId && typeof a.rideId === 'object' ? a.rideId : null
                    const rideId = ride?._id || (typeof a.rideId === 'string' ? a.rideId : '')
                    const riderPhone = a.triggeredBy === 'user' ? a.phone : ride?.riderPhone
                    const driverPhone = a.triggeredBy === 'driver' ? a.phone : ride?.driverPhone
                    return (
                      <tr key={a._id} className={a.status === 'active' ? 'bg-red-50' : a.status === 'acknowledged' ? 'bg-amber-50' : 'hover:bg-gray-50'}>
                        <td className="px-4 py-3 text-gray-600 whitespace-nowrap">{fmt(a.createdAt)}</td>
                        <td className="px-4 py-3 text-xs">
                          <span className={`px-2 py-0.5 rounded-full font-semibold capitalize ${a.status === 'active' ? 'bg-red-600 text-white' : a.status === 'acknowledged' ? 'bg-amber-100 text-amber-800' : 'bg-green-100 text-green-700'}`}>{a.status}</span>
                          {a.acknowledgedBy && <p className="text-gray-500 mt-1 whitespace-nowrap">Seen: {a.acknowledgedBy} · {fmt(a.acknowledgedAt)}</p>}
                          {a.resolvedBy && <p className="text-gray-500 whitespace-nowrap">Resolved: {a.resolvedBy} · {fmt(a.resolvedAt)}</p>}
                          {a.resolutionNote && <p className="text-gray-600 italic max-w-[220px] break-words">&ldquo;{a.resolutionNote}&rdquo;</p>}
                        </td>
                        <td className="px-4 py-3">
                          <span className="text-xs px-2 py-0.5 bg-gray-100 text-gray-700 rounded-full capitalize">{a.triggeredBy === 'user' ? 'rider' : a.triggeredBy}</span>
                        </td>
                        <td className="px-4 py-3 font-medium text-gray-800">{a.name || '—'}</td>
                        <td className="px-4 py-3">
                          {a.phone ? <a href={`tel:${a.phone}`} className="text-blue-600 font-mono">{a.phone}</a> : '—'}
                        </td>
                        <td className="px-4 py-3 text-gray-600">
                          {ride ? `${ride.service || 'ride'} · ${ride.status || ''}` : '—'}
                        </td>
                        <td className="px-4 py-3 text-gray-600 max-w-xs truncate">
                          {a.lat && a.lng ? (
                            <a href={`https://maps.google.com/?q=${a.lat},${a.lng}`} target="_blank" rel="noopener noreferrer" className="text-blue-600">
                              {a.address || `${a.lat.toFixed(4)}, ${a.lng.toFixed(4)}`}
                            </a>
                          ) : (a.address || '—')}
                        </td>
                        <td className="px-4 py-3">
                          <div className="flex flex-wrap gap-1.5 min-w-[220px]">
                            {a.status === 'active' && (
                              <button type="button" onClick={() => actOnAlert(a._id, 'acknowledge').catch(() => {})}
                                className="px-2 py-1 text-xs rounded bg-amber-500 text-white font-semibold hover:bg-amber-600">Acknowledge</button>
                            )}
                            {a.status !== 'resolved' && (
                              <button type="button" onClick={() => { setResolving(a); setResolveNote('') }}
                                className="px-2 py-1 text-xs rounded bg-green-600 text-white font-semibold hover:bg-green-700 flex items-center gap-1"><CheckCircle className="w-3 h-3" />Resolve</button>
                            )}
                            {riderPhone && <a href={`tel:${riderPhone}`} className="px-2 py-1 text-xs rounded border border-blue-200 text-blue-700 hover:bg-blue-50 flex items-center gap-1"><Phone className="w-3 h-3" />Call rider</a>}
                            {driverPhone && <a href={`tel:${driverPhone}`} className="px-2 py-1 text-xs rounded border border-blue-200 text-blue-700 hover:bg-blue-50 flex items-center gap-1"><Phone className="w-3 h-3" />Call driver</a>}
                            {rideId && <Link href={`/rides/${rideId}`} className="px-2 py-1 text-xs rounded border border-gray-200 text-gray-700 hover:bg-gray-50 flex items-center gap-1"><Eye className="w-3 h-3" />Open ride</Link>}
                          </div>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
          <div className="px-4 border-t border-gray-100">
            <Pager page={sosPage} limit={SOS_LIMIT} total={sosTotal} onPage={setSosPage} noun={['alert', 'alerts']} />
          </div>
        </div>

        <div className="bg-red-50 border border-red-200 rounded-xl p-4 flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
          <p className="text-sm text-red-700">
            These contacts are displayed to users when they press the SOS button during a ride. Ensure all numbers are active and verified.
          </p>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-12">
            <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
          </div>
        ) : (
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b border-gray-100">
                  {['Name', 'Phone', 'Relation / Type', 'Added By', 'Actions'].map(h => (
                    <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {contacts.map(c => (
                  <tr key={c._id} className="hover:bg-gray-50">
                    <td className="px-4 py-3 font-medium text-gray-800">{c.name}</td>
                    <td className="px-4 py-3">
                      <a href={`tel:${c.phone}`} className="flex items-center gap-1.5 text-blue-600 hover:text-blue-800">
                        <Phone className="w-3.5 h-3.5" />
                        <span className="font-mono">{c.phone}</span>
                      </a>
                    </td>
                    <td className="px-4 py-3 text-gray-600">{c.relation}</td>
                    <td className="px-4 py-3">
                      <span className="text-xs px-2 py-0.5 bg-blue-100 text-blue-700 rounded-full capitalize">{c.addedBy}</span>
                    </td>
                    <td className="px-4 py-3">
                      <button type="button" title="Remove contact" onClick={() => setDeleting(c)}
                        className="p-1.5 hover:bg-red-50 rounded-lg text-red-400 hover:text-red-600">
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))}
                {contacts.length === 0 && (
                  <tr><td colSpan={5} className="text-center text-gray-400 py-12">No SOS contacts yet</td></tr>
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {showModal && (
        <Modal title="Add SOS Contact" onClose={() => setShowModal(false)} size="sm">
          <form onSubmit={handleAdd} className="space-y-4">
            <div>
              <label htmlFor="sosName" className="block text-sm font-medium text-gray-700 mb-1">Name *</label>
              <input id="sosName" required value={form.name} onChange={e => setForm({ ...form, name: e.target.value })}
                placeholder="e.g. Local Police Station"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div>
              <label htmlFor="sosPhone" className="block text-sm font-medium text-gray-700 mb-1">Phone Number *</label>
              <input id="sosPhone" required value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })}
                placeholder="100 or +91 XXXXX XXXXX"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div>
              <label htmlFor="sosRelation" className="block text-sm font-medium text-gray-700 mb-1">Relation / Type *</label>
              <input id="sosRelation" required value={form.relation} onChange={e => setForm({ ...form, relation: e.target.value })}
                placeholder="e.g. Emergency, Support"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setShowModal(false)}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">Cancel</button>
              <button type="submit"
                className="flex-1 bg-red-600 text-white rounded-lg py-2 text-sm font-medium hover:bg-red-700">Add Contact</button>
            </div>
          </form>
        </Modal>
      )}

      {resolving && (
        <Modal title="Resolve SOS" onClose={() => setResolving(null)} size="sm">
          <form className="space-y-4" onSubmit={async e => {
            e.preventDefault()
            try { await actOnAlert(resolving._id, 'resolve', resolveNote); setResolving(null) } catch { /* toast shown */ }
          }}>
            <p className="text-sm text-gray-700">
              SOS from <strong>{resolving.name || resolving.phone || 'unknown'}</strong> raised {fmt(resolving.createdAt)}.
            </p>
            <div>
              <label htmlFor="sosNote" className="block text-sm font-medium text-gray-700 mb-1">How was it resolved? *</label>
              <textarea id="sosNote" required minLength={3} rows={3} value={resolveNote} onChange={e => setResolveNote(e.target.value)}
                placeholder="e.g. Called the rider — false alarm, rider is safe"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-green-500" />
            </div>
            <div className="flex gap-3">
              <button type="button" onClick={() => setResolving(null)} className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">Cancel</button>
              <button type="submit" disabled={resolveNote.trim().length < 3} className="flex-1 bg-green-600 text-white rounded-lg py-2 text-sm font-medium hover:bg-green-700 disabled:opacity-50">Mark resolved</button>
            </div>
          </form>
        </Modal>
      )}

      {deleting && (
        <ConfirmDialog title="Remove SOS contact" confirmLabel="Remove"
          message={<>Remove <strong>{deleting.name}</strong> ({deleting.phone}) from the SOS contacts shown to riders?</>}
          onConfirm={() => deleteContact(deleting._id)} onClose={() => setDeleting(null)} />
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}

'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { Plus, Trash2, ToggleLeft, ToggleRight } from 'lucide-react'

const DAYS = ['all', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'] as const
type Day = typeof DAYS[number]

interface SurgeRule {
  _id: string
  zoneId: string
  zoneName?: string
  dayOfWeek: Day
  startTime: string
  endTime: string
  surgeMultiplier: number
  isActive: boolean
  reason?: string
}

interface Zone { _id: string; name: string }

const defaultForm = {
  zoneId: '',
  zoneName: '',
  dayOfWeek: 'all' as Day,
  startTime: '08:00',
  endTime: '10:00',
  surgeMultiplier: 1.5,
  isActive: true,
  reason: '',
}

const DAY_LABELS: Record<Day, string> = {
  all: 'Every Day', monday: 'Monday', tuesday: 'Tuesday', wednesday: 'Wednesday',
  thursday: 'Thursday', friday: 'Friday', saturday: 'Saturday', sunday: 'Sunday',
}

export default function SurgePricingPage() {
  const [surges, setSurges] = useState<SurgeRule[]>([])
  const [zones, setZones] = useState<Zone[]>([])
  const [loading, setLoading] = useState(true)
  const [showModal, setShowModal] = useState(false)
  const [form, setForm] = useState(defaultForm)
  const [saving, setSaving] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const fetchSurges = () =>
    fetch('/api/surge').then(r => r.json()).then(d => { setSurges(d.surges || []); setLoading(false) }).catch(() => setLoading(false))

  const fetchZones = () =>
    fetch('/api/zones').then(r => r.json()).then(d => setZones(d.zones || [])).catch(() => {})

  useEffect(() => { fetchSurges(); fetchZones() }, [])

  const openAdd = () => { setForm(defaultForm); setShowModal(true) }

  const handleZoneChange = (zoneId: string) => {
    const zone = zones.find(z => z._id === zoneId)
    setForm({ ...form, zoneId, zoneName: zone?.name ?? '' })
  }

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.zoneId) { setToast({ msg: 'Please select a zone', type: 'error' }); return }
    setSaving(true)
    const res = await fetch('/api/surge', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(form),
    })
    setSaving(false)
    if (res.ok) {
      setShowModal(false)
      fetchSurges()
      setToast({ msg: 'Surge rule added', type: 'success' })
    } else {
      setToast({ msg: 'Failed to add surge rule', type: 'error' })
    }
  }

  const handleToggle = async (surge: SurgeRule) => {
    const res = await fetch(`/api/surge/${surge._id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ isActive: !surge.isActive }),
    })
    if (res.ok) setSurges(prev => prev.map(s => s._id === surge._id ? { ...s, isActive: !surge.isActive } : s))
  }

  const handleDelete = async (id: string) => {
    if (!confirm('Delete this surge rule?')) return
    const res = await fetch(`/api/surge/${id}`, { method: 'DELETE' })
    if (res.ok) { fetchSurges(); setToast({ msg: 'Surge rule deleted', type: 'success' }) }
  }

  // Group by zone name
  const grouped = surges.reduce<Record<string, SurgeRule[]>>((acc, s) => {
    const key = s.zoneName || s.zoneId
    acc[key] = acc[key] ? [...acc[key], s] : [s]
    return acc
  }, {})

  if (loading) return (
    <div>
      <Header title="Surge Pricing" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  return (
    <div>
      <Header title="Surge Pricing" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="Surge Pricing Schedules"
          subtitle="Time-based surge multipliers per zone"
          action={
            <button type="button" onClick={openAdd}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-lg text-sm font-medium hover:bg-primary-dark">
              <Plus className="w-4 h-4" /> Add Surge Rule
            </button>
          }
        />

        {Object.keys(grouped).length === 0 ? (
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-12 text-center text-gray-400">
            No surge rules yet. Add one to start.
          </div>
        ) : (
          Object.entries(grouped).map(([zoneName, rules]) => (
            <div key={zoneName} className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden">
              <div className="px-5 py-3 bg-gray-50 border-b border-gray-100">
                <h3 className="font-semibold text-gray-800 text-sm">{zoneName}</h3>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-gray-100 text-left">
                      <th className="px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Day</th>
                      <th className="px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Start</th>
                      <th className="px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">End</th>
                      <th className="px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Multiplier</th>
                      <th className="px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Reason</th>
                      <th className="px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Active</th>
                      <th className="px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide"></th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-50">
                    {rules.map(s => (
                      <tr key={s._id} className="hover:bg-gray-50 transition-colors">
                        <td className="px-5 py-3 font-medium text-gray-800">{DAY_LABELS[s.dayOfWeek]}</td>
                        <td className="px-5 py-3 text-gray-600">{s.startTime}</td>
                        <td className="px-5 py-3 text-gray-600">{s.endTime}</td>
                        <td className="px-5 py-3">
                          <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-semibold bg-amber-100 text-amber-800">
                            {s.surgeMultiplier}x
                          </span>
                        </td>
                        <td className="px-5 py-3 text-gray-500">{s.reason || '—'}</td>
                        <td className="px-5 py-3">
                          <button type="button" onClick={() => handleToggle(s)} title="Toggle surge rule active state"
                            className="text-gray-500 hover:text-gray-700">
                            {s.isActive
                              ? <ToggleRight className="w-5 h-5 text-green-600" />
                              : <ToggleLeft className="w-5 h-5 text-gray-400" />}
                          </button>
                        </td>
                        <td className="px-5 py-3">
                          <button type="button" onClick={() => handleDelete(s._id)} title="Delete surge rule"
                            className="p-1.5 hover:bg-red-50 rounded-lg text-red-500">
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          ))
        )}
      </div>

      {showModal && (
        <Modal title="Add Surge Rule" onClose={() => setShowModal(false)}>
          <form onSubmit={handleSave} className="space-y-4">
            <div>
              <label htmlFor="surge-zone" className="block text-sm font-medium text-gray-700 mb-1">Zone *</label>
              <select id="surge-zone" required value={form.zoneId} onChange={e => handleZoneChange(e.target.value)}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
                <option value="">Select a zone</option>
                {zones.map(z => <option key={z._id} value={z._id}>{z.name}</option>)}
              </select>
            </div>
            <div>
              <label htmlFor="surge-day" className="block text-sm font-medium text-gray-700 mb-1">Day of Week</label>
              <select id="surge-day" value={form.dayOfWeek} onChange={e => setForm({ ...form, dayOfWeek: e.target.value as Day })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
                {DAYS.map(d => <option key={d} value={d}>{DAY_LABELS[d]}</option>)}
              </select>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label htmlFor="surge-start" className="block text-sm font-medium text-gray-700 mb-1">Start Time</label>
                <input id="surge-start" type="time" value={form.startTime}
                  onChange={e => setForm({ ...form, startTime: e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="surge-end" className="block text-sm font-medium text-gray-700 mb-1">End Time</label>
                <input id="surge-end" type="time" value={form.endTime}
                  onChange={e => setForm({ ...form, endTime: e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
            </div>
            <div>
              <label htmlFor="surge-multiplier" className="block text-sm font-medium text-gray-700 mb-1">Surge Multiplier</label>
              <input id="surge-multiplier" type="number" step="0.1" min="1" value={form.surgeMultiplier}
                onChange={e => setForm({ ...form, surgeMultiplier: +e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              <p className="text-xs text-gray-400 mt-1">e.g. 1.5 = 50% more than base fare</p>
            </div>
            <div>
              <label htmlFor="surge-reason" className="block text-sm font-medium text-gray-700 mb-1">Reason (optional)</label>
              <input id="surge-reason" type="text" placeholder="e.g. Morning rush, Evening peak" value={form.reason}
                onChange={e => setForm({ ...form, reason: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div className="flex items-center gap-3">
              <input id="surge-active" type="checkbox" checked={form.isActive}
                onChange={e => setForm({ ...form, isActive: e.target.checked })}
                className="w-4 h-4 rounded text-blue-600 border-gray-300 focus:ring-blue-500" />
              <label htmlFor="surge-active" className="text-sm font-medium text-gray-700 cursor-pointer">Active immediately</label>
            </div>
            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setShowModal(false)}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">
                Cancel
              </button>
              <button type="submit" disabled={saving}
                className="flex-1 bg-primary text-white rounded-lg py-2 text-sm font-medium hover:bg-primary-dark disabled:opacity-60">
                {saving ? 'Saving...' : 'Add Rule'}
              </button>
            </div>
          </form>
        </Modal>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}

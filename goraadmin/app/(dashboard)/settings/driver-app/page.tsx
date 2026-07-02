'use client'
import { useEffect, useState } from 'react'

const TABS = ['Subscription Plans', 'Wallet Rules'] as const
const SERVICES = ['taxi', 'rental', 'outstation', 'delivery', 'hire_driver']

export default function DriverAppSettings() {
  const [tab, setTab] = useState<string>('Subscription Plans')
  const [plans, setPlans] = useState<any[]>([])
  const [editIdx, setEditIdx] = useState<number>(-1)
  const [settings, setSettings] = useState<any>(null)
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => { load() }, [])
  async function load() {
    const [p, s] = await Promise.all([
      fetch('/api/subscription-plans').then(r => r.json()),
      fetch('/api/settings').then(r => r.json()),
    ])
    setPlans(p.plans || [])
    setSettings(s || {})
  }

  const flash = (m: string) => { setMsg(m); setTimeout(() => setMsg(''), 2500) }
  const inp = 'w-full border border-gray-300 rounded px-2 py-1.5 text-sm'

  // ── Plan helpers ──
  const updPlan = (i: number, field: string, val: any) =>
    setPlans(plans.map((p, x) => x === i ? { ...p, [field]: val } : p))

  const toggleService = (i: number, svc: string) => {
    const cur: string[] = plans[i].services || []
    const next = cur.includes(svc) ? cur.filter(s => s !== svc) : [...cur, svc]
    updPlan(i, 'services', next)
  }

  async function savePlan(i: number) {
    setBusy(true)
    const p = plans[i]
    const body = {
      name: p.name, price: Number(p.price) || 0, durationDays: Number(p.durationDays) || 30,
      description: p.description || '', benefits: p.benefits || [],
      commissionPercentWhileActive: Number(p.commissionPercentWhileActive) || 0,
      services: p.services || [], vehicleTypes: p.vehicleTypes || [],
      isActive: p.isActive !== false, sortOrder: Number(p.sortOrder) || 0,
    }
    try {
      if (p._id) await fetch(`/api/subscription-plans/${p._id}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
      else await fetch('/api/subscription-plans', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
      await load(); setEditIdx(-1); flash('Plan saved ✓')
    } catch { flash('Failed') }
    setBusy(false)
  }

  async function delPlan(i: number) {
    const p = plans[i]
    setEditIdx(-1)
    if (!p._id) { setPlans(plans.filter((_, x) => x !== i)); return }
    setBusy(true)
    try { await fetch(`/api/subscription-plans/${p._id}`, { method: 'DELETE' }); await load(); flash('Plan deleted') }
    catch { flash('Failed') }
    setBusy(false)
  }

  const addPlan = () => {
    setPlans([...plans, {
      name: 'New Plan', price: 0, durationDays: 30, description: '', benefits: [],
      commissionPercentWhileActive: 0, services: [], vehicleTypes: [], isActive: true, sortOrder: plans.length,
    }])
    setEditIdx(plans.length)
  }

  async function saveWalletRules() {
    setBusy(true)
    try {
      const body = { ...settings, driverApp: { ...(settings.driverApp || {}) } }
      await fetch('/api/settings', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
      flash('Wallet rules saved ✓')
    } catch { flash('Failed') }
    setBusy(false)
  }

  const setDriverApp = (field: string, val: any) =>
    setSettings({ ...settings, driverApp: { ...(settings?.driverApp || {}), [field]: val } })

  if (!settings) return <div className="p-8 text-gray-500">Loading…</div>
  const da = settings.driverApp || {}

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-5">
        <div>
          <h1 className="text-2xl font-bold">Driver App</h1>
          <p className="text-sm text-gray-500">Manage driver subscription plans and wallet rules.</p>
        </div>
        {msg && <span className="text-sm font-semibold text-green-600">{msg}</span>}
      </div>

      <div className="flex gap-6 items-start">
        {/* Left menu */}
        <div className="w-52 flex-shrink-0 bg-white border border-gray-100 rounded-xl p-2 sticky top-4">
          {TABS.map(t => (
            <button type="button" key={t} onClick={() => setTab(t)}
              className={`w-full text-left px-3 py-2.5 rounded-lg text-sm font-semibold mb-1 transition-colors ${tab === t ? 'bg-[#1C2656] text-white' : 'text-gray-600 hover:bg-gray-100'}`}>{t}</button>
          ))}
        </div>

        {/* Content */}
        <div className="flex-1 max-w-3xl">
          {tab === 'Subscription Plans' && (
            <div className="space-y-3">
              {plans.map((p, i) => editIdx === i ? (
                /* ── Edit form ── */
                <div key={p._id || i} className="bg-white border-2 border-[#1C2656] rounded-xl p-4 space-y-2">
                  <div className="grid grid-cols-2 gap-2">
                    <div><label className="block text-xs text-gray-500 mb-1">Plan name</label>
                      <input className={inp} title="Plan name" placeholder="Weekly Pass" value={p.name || ''} onChange={e => updPlan(i, 'name', e.target.value)} /></div>
                    <div><label className="block text-xs text-gray-500 mb-1">Price (₹)</label>
                      <input className={inp} type="number" title="Price" placeholder="149" value={p.price ?? 0} onChange={e => updPlan(i, 'price', +e.target.value)} /></div>
                    <div><label className="block text-xs text-gray-500 mb-1">Duration (days)</label>
                      <input className={inp} type="number" title="Duration days" placeholder="7" value={p.durationDays ?? 30} onChange={e => updPlan(i, 'durationDays', +e.target.value)} /></div>
                    <div><label className="block text-xs text-gray-500 mb-1">Commission while active (%)</label>
                      <input className={inp} type="number" title="Commission while active" placeholder="0" value={p.commissionPercentWhileActive ?? 0} onChange={e => updPlan(i, 'commissionPercentWhileActive', +e.target.value)} /></div>
                  </div>
                  <div><label className="block text-xs text-gray-500 mb-1">Description</label>
                    <input className={inp} title="Description" placeholder="Short line shown to driver" value={p.description || ''} onChange={e => updPlan(i, 'description', e.target.value)} /></div>
                  <div><label className="block text-xs text-gray-500 mb-1">Benefits (one per line)</label>
                    <textarea className={inp} rows={3} title="Benefits" placeholder={'Zero commission\nUnlimited rides\nPriority support'}
                      value={(p.benefits || []).join('\n')} onChange={e => updPlan(i, 'benefits', e.target.value.split('\n').map(s => s.trim()).filter(Boolean))} /></div>
                  <div>
                    <label className="block text-xs text-gray-500 mb-1">Applies to services (none = all)</label>
                    <div className="flex flex-wrap gap-3">
                      {SERVICES.map(svc => (
                        <label key={svc} className="text-xs flex items-center gap-1 capitalize">
                          <input type="checkbox" checked={(p.services || []).includes(svc)} onChange={() => toggleService(i, svc)} /> {svc.replace('_', ' ')}
                        </label>
                      ))}
                    </div>
                  </div>
                  <div className="flex items-center justify-between pt-1">
                    <label className="text-xs flex items-center gap-1"><input type="checkbox" checked={p.isActive !== false} onChange={e => updPlan(i, 'isActive', e.target.checked)} /> Active</label>
                    <div className="flex gap-2">
                      <button type="button" onClick={() => { if (!p._id) delPlan(i); else setEditIdx(-1) }} className="px-4 py-1.5 rounded-lg text-sm font-semibold border border-gray-300 text-gray-600 hover:bg-gray-50">Cancel</button>
                      <button type="button" onClick={() => savePlan(i)} disabled={busy} className="bg-[#1C2656] text-white px-5 py-1.5 rounded-lg text-sm font-semibold disabled:opacity-50">{p._id ? 'Save' : 'Create'}</button>
                    </div>
                  </div>
                </div>
              ) : (
                /* ── Preview card (same look as the driver app) ── */
                <div key={p._id || i} className="bg-white border border-gray-100 rounded-xl p-4 shadow-sm">
                  <div className="flex items-start justify-between">
                    <div>
                      <div className="flex items-center gap-2">
                        <h3 className="font-extrabold text-gray-800 text-base">{p.name}</h3>
                        {p.isActive === false && <span className="text-[10px] bg-gray-100 text-gray-500 px-2 py-0.5 rounded-full font-semibold">INACTIVE</span>}
                      </div>
                      <p className="text-xs text-gray-500 mt-0.5">{p.durationDays} days • {(+p.commissionPercentWhileActive || 0) === 0 ? 'Zero commission' : `${p.commissionPercentWhileActive}% commission`}</p>
                    </div>
                    <div className="text-2xl font-black text-[#1C2656]">₹{p.price}</div>
                  </div>
                  {p.description && <p className="text-sm text-gray-500 mt-1">{p.description}</p>}
                  {(p.benefits || []).length > 0 && (
                    <ul className="mt-2 space-y-1">
                      {(p.benefits || []).map((b: string, bi: number) => (
                        <li key={bi} className="flex items-center gap-2 text-sm text-gray-700"><span className="text-green-600 font-bold">✓</span>{b}</li>
                      ))}
                    </ul>
                  )}
                  {(p.services || []).length > 0 && <p className="text-xs text-gray-400 mt-2">Services: {(p.services || []).join(', ')}</p>}
                  <div className="flex items-center justify-end gap-2 mt-3 pt-3 border-t border-gray-100">
                    <button type="button" onClick={() => setEditIdx(i)} className="px-4 py-1.5 rounded-lg text-sm font-semibold border border-[#1C2656] text-[#1C2656] hover:bg-[#1C2656]/5">✎ Edit</button>
                    <button type="button" onClick={() => delPlan(i)} className="px-4 py-1.5 rounded-lg text-sm font-semibold border border-red-300 text-red-600 hover:bg-red-50">🗑 Delete</button>
                  </div>
                </div>
              ))}
              <button type="button" onClick={addPlan} className="text-sm font-semibold text-[#1C2656] border border-dashed border-[#1C2656] rounded-lg px-4 py-2 w-full hover:bg-[#1C2656]/5">+ Add Plan</button>
            </div>
          )}

          {tab === 'Wallet Rules' && (
            <div className="bg-white border rounded-xl p-5 space-y-4 max-w-md">
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium text-gray-800">Block rides on low balance</p>
                  <p className="text-xs text-gray-500">Stop sending requests when a driver owes too much commission.</p>
                </div>
                <button type="button" title="Toggle low-balance block" aria-label="Toggle low-balance block"
                  onClick={() => setDriverApp('walletBlockEnabled', !(da.walletBlockEnabled !== false))}
                  className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${da.walletBlockEnabled !== false ? 'bg-[#1C2656]' : 'bg-gray-200'}`}>
                  <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow-sm transition-transform ${da.walletBlockEnabled !== false ? 'translate-x-6' : 'translate-x-1'}`} />
                </button>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Max negative wallet allowed (₹)</label>
                <input className={inp} type="number" title="Max negative wallet" placeholder="500"
                  value={da.maxNegativeWallet ?? 500} onChange={e => setDriverApp('maxNegativeWallet', +e.target.value)} />
                <p className="text-xs text-gray-500 mt-1">Driver can owe up to this much (wallet goes to −₹{da.maxNegativeWallet ?? 500}). Beyond it, no rides until they recharge.</p>
              </div>
              <div className="flex justify-end pt-2 border-t">
                <button type="button" onClick={saveWalletRules} disabled={busy}
                  className="bg-[#1C2656] text-white px-6 py-2 rounded-lg text-sm font-semibold disabled:opacity-50">Save</button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

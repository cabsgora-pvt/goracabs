'use client'
import { useEffect, useState } from 'react'

type Cfg = any
const TABS = ['Banners', 'Offers', 'Coupons', 'Places', 'FAQs', 'Why Choose Us', 'Support', 'Referral'] as const

export default function UserAppSettings() {
  const [cfg, setCfg] = useState<Cfg | null>(null)
  const [tab, setTab] = useState<string>('Banners')
  const [saving, setSaving] = useState(false)
  const [msg, setMsg] = useState('')

  useEffect(() => { load() }, [])
  async function load() {
    const r = await fetch('/api/app-config?app=user').then(r => r.json())
    setCfg(r.config || {})
  }
  async function save() {
    setSaving(true); setMsg('')
    try {
      const r = await fetch('/api/app-config', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...cfg, app: 'user' }) }).then(r => r.json())
      if (r.config) { setCfg(r.config); setMsg('Saved ✓') } else setMsg(r.error || 'Failed')
    } catch (e: any) { setMsg(e.message) }
    setSaving(false)
    setTimeout(() => setMsg(''), 2500)
  }

  if (!cfg) return <div className="p-8 text-gray-500">Loading…</div>

  // helpers to mutate arrays
  const arr = (k: string): any[] => cfg[k] || []
  const setArr = (k: string, v: any[]) => setCfg({ ...cfg, [k]: v })
  const addRow = (k: string, blank: any) => setArr(k, [...arr(k), blank])
  const delRow = (k: string, i: number) => setArr(k, arr(k).filter((_: any, x: number) => x !== i))
  const upd = (k: string, i: number, field: string, val: any) => setArr(k, arr(k).map((row: any, x: number) => x === i ? { ...row, [field]: val } : row))

  const inp = 'w-full border border-gray-300 rounded px-2 py-1.5 text-sm'

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-5">
        <div>
          <h1 className="text-2xl font-bold">User App Content</h1>
          <p className="text-sm text-gray-500">Manage everything the user app shows — banners, offers, coupons, FAQs and more.</p>
        </div>
        <div className="flex items-center gap-3">
          {msg && <span className="text-sm font-semibold text-green-600">{msg}</span>}
          <button type="button" onClick={save} disabled={saving} className="bg-[#1C2656] text-white px-5 py-2 rounded-lg text-sm font-semibold disabled:opacity-50">{saving ? 'Saving…' : 'Save All'}</button>
        </div>
      </div>

      {/* Sidebar layout: vertical menu on the left, content on the right */}
      <div className="flex gap-6 items-start">
        {/* Left vertical menu */}
        <div className="w-52 flex-shrink-0 bg-white border border-gray-100 rounded-xl p-2 sticky top-4">
          {TABS.map(t => (
            <button type="button" key={t} onClick={() => setTab(t)}
              className={`w-full text-left px-3 py-2.5 rounded-lg text-sm font-semibold mb-1 transition-colors ${tab === t ? 'bg-[#1C2656] text-white' : 'text-gray-600 hover:bg-gray-100'}`}>{t}</button>
          ))}
        </div>

        {/* Right content */}
        <div className="flex-1 max-w-3xl">

      {/* BANNERS */}
      {tab === 'Banners' && (
        <Section onAdd={() => addRow('banners', { title: '', subtitle: '', imageUrl: '', color: '#1C2656', isActive: true })}>
          {arr('banners').map((b: any, i: number) => (
            <Card key={i} onDel={() => delRow('banners', i)}>
              <input className={inp} placeholder="Title" value={b.title || ''} onChange={e => upd('banners', i, 'title', e.target.value)} />
              <input className={inp} placeholder="Subtitle" value={b.subtitle || ''} onChange={e => upd('banners', i, 'subtitle', e.target.value)} />
              <input className={inp} placeholder="Image URL" value={b.imageUrl || ''} onChange={e => upd('banners', i, 'imageUrl', e.target.value)} />
              <div className="flex items-center gap-2">
                <input type="color" title="Banner color" aria-label="Banner color" value={b.color || '#1C2656'} onChange={e => upd('banners', i, 'color', e.target.value)} />
                <label className="text-xs flex items-center gap-1"><input type="checkbox" checked={b.isActive !== false} onChange={e => upd('banners', i, 'isActive', e.target.checked)} /> Active</label>
              </div>
            </Card>
          ))}
        </Section>
      )}

      {/* OFFERS */}
      {tab === 'Offers' && (
        <Section onAdd={() => addRow('offers', { title: '', desc: '', imageUrl: '', isActive: true })}>
          {arr('offers').map((o: any, i: number) => (
            <Card key={i} onDel={() => delRow('offers', i)}>
              <input className={inp} placeholder="Title" value={o.title || ''} onChange={e => upd('offers', i, 'title', e.target.value)} />
              <input className={inp} placeholder="Description" value={o.desc || ''} onChange={e => upd('offers', i, 'desc', e.target.value)} />
              <input className={inp} placeholder="Image URL (optional)" value={o.imageUrl || ''} onChange={e => upd('offers', i, 'imageUrl', e.target.value)} />
              <label className="text-xs flex items-center gap-1"><input type="checkbox" checked={o.isActive !== false} onChange={e => upd('offers', i, 'isActive', e.target.checked)} /> Active</label>
            </Card>
          ))}
        </Section>
      )}

      {/* COUPONS */}
      {tab === 'Coupons' && (
        <Section onAdd={() => addRow('coupons', { code: '', discountType: 'flat', value: 0, maxDiscount: 0, minFare: 0, service: 'all', desc: '', isActive: true })}>
          {arr('coupons').map((c: any, i: number) => (
            <Card key={i} onDel={() => delRow('coupons', i)}>
              <input className={inp} placeholder="CODE" value={c.code || ''} onChange={e => upd('coupons', i, 'code', e.target.value.toUpperCase())} />
              <div className="grid grid-cols-2 gap-2">
                <select className={inp} title="Discount type" aria-label="Discount type" value={c.discountType || 'flat'} onChange={e => upd('coupons', i, 'discountType', e.target.value)}>
                  <option value="flat">Flat ₹</option><option value="percent">Percent %</option>
                </select>
                <input className={inp} type="number" placeholder="Value" value={c.value || 0} onChange={e => upd('coupons', i, 'value', +e.target.value)} />
                <input className={inp} type="number" placeholder="Max discount (% cap)" value={c.maxDiscount || 0} onChange={e => upd('coupons', i, 'maxDiscount', +e.target.value)} />
                <input className={inp} type="number" placeholder="Min fare" value={c.minFare || 0} onChange={e => upd('coupons', i, 'minFare', +e.target.value)} />
                <select className={inp} title="Applicable service" aria-label="Applicable service" value={c.service || 'all'} onChange={e => upd('coupons', i, 'service', e.target.value)}>
                  <option value="all">All services</option><option value="taxi">Taxi</option><option value="outstation">Outstation</option><option value="rental">Rental</option><option value="hire_driver">Hire Driver</option><option value="delivery">Parcel</option>
                </select>
                <label className="text-xs flex items-center gap-1"><input type="checkbox" checked={c.isActive !== false} onChange={e => upd('coupons', i, 'isActive', e.target.checked)} /> Active</label>
              </div>
              <input className={inp} placeholder="Description shown to user" value={c.desc || ''} onChange={e => upd('coupons', i, 'desc', e.target.value)} />
            </Card>
          ))}
        </Section>
      )}

      {/* PLACES */}
      {tab === 'Places' && (
        <Section onAdd={() => addRow('places', { name: '', address: '', lat: 0, lng: 0 })}>
          {arr('places').map((p: any, i: number) => (
            <Card key={i} onDel={() => delRow('places', i)}>
              <input className={inp} placeholder="Name" value={p.name || ''} onChange={e => upd('places', i, 'name', e.target.value)} />
              <input className={inp} placeholder="Address" value={p.address || ''} onChange={e => upd('places', i, 'address', e.target.value)} />
              <div className="grid grid-cols-2 gap-2">
                <input className={inp} type="number" placeholder="Lat" value={p.lat || 0} onChange={e => upd('places', i, 'lat', +e.target.value)} />
                <input className={inp} type="number" placeholder="Lng" value={p.lng || 0} onChange={e => upd('places', i, 'lng', +e.target.value)} />
              </div>
            </Card>
          ))}
        </Section>
      )}

      {/* FAQs */}
      {tab === 'FAQs' && (
        <Section onAdd={() => addRow('faqs', { q: '', a: '' })}>
          {arr('faqs').map((f: any, i: number) => (
            <Card key={i} onDel={() => delRow('faqs', i)}>
              <input className={inp} placeholder="Question" value={f.q || ''} onChange={e => upd('faqs', i, 'q', e.target.value)} />
              <textarea className={inp} placeholder="Answer" value={f.a || ''} onChange={e => upd('faqs', i, 'a', e.target.value)} />
            </Card>
          ))}
        </Section>
      )}

      {/* WHY CHOOSE US */}
      {tab === 'Why Choose Us' && (
        <Section onAdd={() => addRow('whyChooseUs', { icon: 'shield', title: '', desc: '' })}>
          {arr('whyChooseUs').map((w: any, i: number) => (
            <Card key={i} onDel={() => delRow('whyChooseUs', i)}>
              <select className={inp} title="Icon" aria-label="Icon" value={w.icon || 'shield'} onChange={e => upd('whyChooseUs', i, 'icon', e.target.value)}>
                <option value="shield">Shield (safety)</option><option value="clock">Clock</option><option value="star">Star</option><option value="money">Money</option><option value="support">Support</option>
              </select>
              <input className={inp} placeholder="Title" value={w.title || ''} onChange={e => upd('whyChooseUs', i, 'title', e.target.value)} />
              <input className={inp} placeholder="Description" value={w.desc || ''} onChange={e => upd('whyChooseUs', i, 'desc', e.target.value)} />
            </Card>
          ))}
        </Section>
      )}

      {/* SUPPORT */}
      {tab === 'Support' && (
        <div className="bg-white border rounded-xl p-4 space-y-3 max-w-md">
          <Field label="Phone"><input className={inp} title="Phone" placeholder="Phone" value={cfg.support?.phone || ''} onChange={e => setCfg({ ...cfg, support: { ...cfg.support, phone: e.target.value } })} /></Field>
          <Field label="Email"><input className={inp} title="Email" placeholder="Email" value={cfg.support?.email || ''} onChange={e => setCfg({ ...cfg, support: { ...cfg.support, email: e.target.value } })} /></Field>
          <Field label="WhatsApp"><input className={inp} title="WhatsApp" placeholder="WhatsApp" value={cfg.support?.whatsapp || ''} onChange={e => setCfg({ ...cfg, support: { ...cfg.support, whatsapp: e.target.value } })} /></Field>
          <Field label="Address"><input className={inp} title="Address" placeholder="Address" value={cfg.support?.address || ''} onChange={e => setCfg({ ...cfg, support: { ...cfg.support, address: e.target.value } })} /></Field>
        </div>
      )}

      {/* REFERRAL */}
      {tab === 'Referral' && (
        <div className="bg-white border rounded-xl p-4 space-y-3 max-w-md">
          <Field label="Reward Amount (₹)"><input className={inp} title="Reward amount" placeholder="Reward amount" type="number" value={cfg.referral?.rewardAmount || 0} onChange={e => setCfg({ ...cfg, referral: { ...cfg.referral, rewardAmount: +e.target.value } })} /></Field>
          <Field label="Message"><input className={inp} title="Message" placeholder="Message" value={cfg.referral?.message || ''} onChange={e => setCfg({ ...cfg, referral: { ...cfg.referral, message: e.target.value } })} /></Field>
        </div>
      )}

        </div>
      </div>
    </div>
  )
}

function Section({ children, onAdd }: { children: React.ReactNode; onAdd: () => void }) {
  return (
    <div className="space-y-3">
      {children}
      <button type="button" onClick={onAdd} className="text-sm font-semibold text-[#1C2656] border border-dashed border-[#1C2656] rounded-lg px-4 py-2 w-full hover:bg-[#1C2656]/5">+ Add</button>
    </div>
  )
}
function Card({ children, onDel }: { children: React.ReactNode; onDel: () => void }) {
  return (
    <div className="bg-white border rounded-xl p-3 space-y-2 relative">
      <button type="button" onClick={onDel} className="absolute top-2 right-2 text-red-500 text-xs font-bold">✕ Remove</button>
      {children}
    </div>
  )
}
function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <div><label className="block text-xs font-medium text-gray-600 mb-1">{label}</label>{children}</div>
}

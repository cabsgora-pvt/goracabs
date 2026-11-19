'use client'
import { useState } from 'react'
import { FileText } from 'lucide-react'
import { Header } from '@/components/header'
import { Toast } from '@/components/ui/toast'
import { useZoneAdmin, useZoneReload, useZoneSession, zoneFetch } from '@/components/zone-shell'
import { daysLeft, fmtDate } from '@/lib/zone-admin-ui'

const input = 'w-full border border-[#ced4da] rounded px-3 py-2 text-[13px] focus:outline-none focus:border-[#a0a8c4]'

export default function ZoneProfile() {
  const me = useZoneAdmin()
  const session = useZoneSession()
  const reload = useZoneReload()
  const [pw, setPw] = useState({ current: '', next: '' })
  const [phones, setPhones] = useState<Record<string, string>>({})
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)
  if (!me || !session) return null
  const left = daysLeft(me.subscriptionEndAt)
  const owner = session.isOwner
  const row = (k: string, v?: string) => (
    <div className="flex justify-between gap-4 py-2 border-b border-[#f3f3f9] text-[13px]">
      <span className="text-[#878a99]">{k}</span><span className="text-[#495057] text-right">{v || '—'}</span>
    </div>
  )

  const changePassword = async (e: React.FormEvent) => {
    e.preventDefault()
    const r = await zoneFetch('/api/zone-admin/password', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(pw) })
    const x = await r.json()
    if (!r.ok) { setToast({ msg: x.error || 'Could not change password', type: 'error' }); return }
    setPw({ current: '', next: '' }); setToast({ msg: 'Password changed', type: 'success' })
  }
  const savePhone = async (zoneId: string) => {
    const r = await zoneFetch('/api/zone-admin/zone-settings', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ zoneId, supportPhone: phones[zoneId] ?? '' }) })
    const x = await r.json()
    if (!r.ok) { setToast({ msg: x.error || 'Could not save', type: 'error' }); return }
    setToast({ msg: 'Helpline saved — riders in this zone will see it', type: 'success' }); reload()
  }

  return (
    <div>
      <Header title="My Profile" />
      <div className="p-6 grid lg:grid-cols-2 gap-5">
        <div className="space-y-5">
          <div className="bg-white rounded shadow-sm p-5">
            <div className="flex items-center gap-4 mb-4">
              <div className="w-14 h-14 rounded-full bg-primary text-white flex items-center justify-center text-xl font-semibold">{session.actor.name?.[0]?.toUpperCase()}</div>
              <div>
                <h3 className="text-[17px] font-semibold text-[#495057]">{session.actor.type === 'staff' ? session.actor.name : me.name}</h3>
                <p className="text-[13px] text-gray-500">{session.actor.type === 'staff' ? `Staff of ${me.businessName || me.name}` : (me.businessName || 'Zone Admin')}</p>
              </div>
            </div>
            {owner && <>
              {row('Email', me.email)}
              {row('Phone', me.phone)}
              {row('Address', me.address)}
              {row('GST number', me.gstNumber)}
            </>}
            {row('Zones', me.zones.map(z => z.name).join(', '))}
            {owner && <p className="text-xs text-gray-500 mt-3">To change these details, contact Gora.</p>}
          </div>

          {!session.impersonatedBy && (
            <form onSubmit={changePassword} className="bg-white rounded shadow-sm p-5 space-y-3">
              <h5 className="font-semibold text-[15px] text-[#495057]">Change password</h5>
              <input type="password" required className={input} placeholder="Current password" value={pw.current} onChange={e => setPw({ ...pw, current: e.target.value })} />
              <input type="password" required minLength={8} className={input} placeholder="New password (min 8)" value={pw.next} onChange={e => setPw({ ...pw, next: e.target.value })} />
              <button type="submit" className="px-4 py-2 rounded bg-primary text-white text-[13px]">Change password</button>
            </form>
          )}

          {owner && (
            <div className="bg-white rounded shadow-sm p-5 space-y-3">
              <h5 className="font-semibold text-[15px] text-[#495057]">Zone helpline for riders</h5>
              <p className="text-[12.5px] text-gray-500">Shown in the rider app&apos;s Help &amp; Support when a rider is in your zone.</p>
              {me.zones.map(z => (
                <div key={z._id} className="flex gap-2 items-center">
                  <span className="w-28 text-[13px] text-[#495057]">{z.name}</span>
                  <input className={input} disabled={session.readOnly} placeholder="+91 98765 43210" value={phones[z._id] ?? z.supportPhone ?? ''}
                    onChange={e => setPhones({ ...phones, [z._id]: e.target.value })} />
                  <button type="button" disabled={session.readOnly} onClick={() => savePhone(z._id)} className="px-3 py-2 rounded bg-primary text-white text-[13px] disabled:opacity-50">Save</button>
                </div>
              ))}
            </div>
          )}
        </div>

        {owner && (
          <div className="bg-white rounded shadow-sm p-5 self-start">
            <h5 className="font-semibold text-[15px] text-[#495057] mb-2">Subscription</h5>
            <p className="text-[13px] text-gray-600">
              Valid till <b>{fmtDate(me.subscriptionEndAt)}</b>
              {left !== null && ` · ${left > 0 ? `${left} day${left === 1 ? '' : 's'} left` : 'ended'}`}
            </p>
            <p className="text-[12px] text-gray-500 mt-1">When it ends the panel turns read-only for a few days, then locks until Gora records your renewal.</p>
            <p className="text-[13px] font-semibold text-[#495057] mt-5 mb-2">Payments</p>
            <table className="w-full text-[12.5px]">
              <thead><tr>{['Date', 'Plan', 'Period', 'Amount', ''].map(h => <th key={h} className="text-left px-2 py-2">{h}</th>)}</tr></thead>
              <tbody className="divide-y">
                {me.payments.length === 0 ? <tr><td colSpan={5} className="text-center py-4 text-gray-400">No payments</td></tr> :
                  me.payments.map((p: any) => (
                    <tr key={p._id}>
                      <td className="px-2 py-2">{fmtDate(p.createdAt)}</td>
                      <td className="px-2 py-2">{p.planName}</td>
                      <td className="px-2 py-2">{fmtDate(p.periodStart)} – {fmtDate(p.periodEnd)}</td>
                      <td className="px-2 py-2">₹{Math.round(p.amount).toLocaleString('en-IN')}</td>
                      <td className="px-2 py-2"><a href={`/zone-panel/invoice/${p._id}`} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-primary"><FileText className="w-3.5 h-3.5" />Invoice</a></td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}

'use client'
import { useEffect, useState } from 'react'
import { Printer } from 'lucide-react'
import { fmtDate } from '@/lib/zone-admin-ui'

// Printable invoice for a zone admin subscription payment. "Download PDF" is
// the browser's own print → Save as PDF, so no PDF library is needed.
export function ZoneInvoice({ url }: { url: string }) {
  const [inv, setInv] = useState<any>(null)
  const [err, setErr] = useState('')
  useEffect(() => {
    fetch(url).then(async r => {
      const d = await r.json()
      if (!r.ok) setErr(d.error || 'Could not load invoice'); else setInv(d.invoice)
    }).catch(() => setErr('Could not load invoice'))
  }, [url])

  if (err) return <p className="p-6 text-red-600">{err}</p>
  if (!inv) return <p className="p-6 text-gray-400">Loading…</p>
  const rupee = (n: number) => `₹${Number(n || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

  return (
    <div className="p-6 print:p-0">
      <div className="flex justify-end mb-4 print:hidden">
        <button type="button" onClick={() => window.print()} className="inline-flex items-center gap-2 bg-primary text-white px-4 py-2 rounded text-[13px]">
          <Printer className="w-4 h-4" /> Print / Save as PDF
        </button>
      </div>
      <div className="bg-white max-w-3xl mx-auto p-8 rounded shadow-sm print:shadow-none text-[13px] text-[#212529]">
        <div className="flex justify-between gap-6 border-b pb-5">
          <div>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/gora-logo.png" alt="" className="h-10 w-auto mb-2" />
            <p className="font-semibold text-[15px]">{inv.company.name}</p>
            {inv.company.address && <p className="text-gray-600 whitespace-pre-line">{inv.company.address}</p>}
            {inv.company.gstin && <p className="text-gray-600">GSTIN: {inv.company.gstin}</p>}
            <p className="text-gray-600">{[inv.company.phone, inv.company.email].filter(Boolean).join(' · ')}</p>
          </div>
          <div className="text-right">
            <h2 className="text-[22px] font-bold text-[#405189]">{inv.gstPercent ? 'TAX INVOICE' : 'INVOICE'}</h2>
            <p className="mt-2"><span className="text-gray-500">Invoice no:</span> <b>{inv.invoiceNo}</b></p>
            <p><span className="text-gray-500">Date:</span> {fmtDate(inv.date)}</p>
            {inv.paymentRef && <p><span className="text-gray-500">Payment ref:</span> {inv.paymentRef}</p>}
          </div>
        </div>

        <div className="py-5 border-b">
          <p className="text-gray-500 text-[12px] uppercase font-semibold mb-1">Bill to</p>
          <p className="font-semibold">{inv.billTo.name}</p>
          {inv.billTo.name !== inv.billTo.contact && <p>{inv.billTo.contact}</p>}
          {inv.billTo.address && <p className="text-gray-600">{inv.billTo.address}</p>}
          <p className="text-gray-600">{[inv.billTo.phone, inv.billTo.email].filter(Boolean).join(' · ')}</p>
          {inv.billTo.gstin && <p className="text-gray-600">GSTIN: {inv.billTo.gstin}</p>}
        </div>

        <table className="w-full mt-5">
          <thead>
            <tr><th className="text-left px-3 py-2">Description</th><th className="text-left px-3 py-2">Period</th><th className="text-right px-3 py-2">Amount</th></tr>
          </thead>
          <tbody>
            <tr className="border-b">
              <td className="px-3 py-3">Gora zone admin subscription — {inv.planName} ({inv.months} month{inv.months > 1 ? 's' : ''})</td>
              <td className="px-3 py-3">{fmtDate(inv.periodStart)} – {fmtDate(inv.periodEnd)}</td>
              <td className="px-3 py-3 text-right">{rupee(inv.taxable)}</td>
            </tr>
          </tbody>
        </table>
        <div className="flex justify-end mt-4">
          <div className="w-64 space-y-1">
            <div className="flex justify-between"><span className="text-gray-500">Taxable value</span><span>{rupee(inv.taxable)}</span></div>
            {inv.gstPercent > 0 && <div className="flex justify-between"><span className="text-gray-500">GST @ {inv.gstPercent}%</span><span>{rupee(inv.tax)}</span></div>}
            <div className="flex justify-between border-t pt-2 font-semibold text-[15px]"><span>Total paid</span><span>{rupee(inv.total)}</span></div>
          </div>
        </div>
        <p className="text-[11.5px] text-gray-500 mt-8">This is a computer-generated invoice. {inv.gstPercent ? 'Amount includes GST.' : ''}</p>
      </div>
    </div>
  )
}

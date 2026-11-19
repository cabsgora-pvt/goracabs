'use client'
import { useParams } from 'next/navigation'
import { ZoneInvoice } from '@/components/zone-invoice'

// Zone admin's own subscription invoice (no panel chrome, for printing).
export default function ZoneAdminInvoice() {
  const { pid } = useParams<{ pid: string }>()
  return <div className="min-h-screen bg-[#f3f3f9] print:bg-white"><ZoneInvoice url={`/api/zone-admin/payments/${pid}`} /></div>
}

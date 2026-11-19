'use client'
import { useParams } from 'next/navigation'
import { ZoneInvoice } from '@/components/zone-invoice'

// Super admin's copy of a zone admin subscription invoice (no panel chrome, for printing).
export default function SuperAdminZoneInvoice() {
  const { id, pid } = useParams<{ id: string; pid: string }>()
  return <div className="min-h-screen bg-[#f3f3f9] print:bg-white"><ZoneInvoice url={`/api/zone-admins/${id}/payments/${pid}`} /></div>
}

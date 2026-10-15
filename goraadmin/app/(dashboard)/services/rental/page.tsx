'use client'
import Link from 'next/link'
import { useEffect, useState } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { MapPin, AlertTriangle } from 'lucide-react'

// This page used to present baseFare / perKm / perMin / minFare / night
// surcharge / commission inputs and save them to ServiceConfig(service:'rental').
// Nothing in the rental flow has ever read that record — rental is priced
// entirely from Zone.rentalPackages (see /api/rental/packages and
// lib/rental-pricing.ts). Editing it looked like it changed prices and did not.
//
// Rather than leave a convincing but inert form, it now points at the screen
// that actually controls rental pricing.
export default function RentalServicePage() {
  const [zones, setZones] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetch('/api/zones')
      .then(r => r.json())
      .then(d => { setZones(d.zones || d || []); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  return (
    <div>
      <Header title="Rental Pricing" />
      <div className="p-6 space-y-6">
        <PageHeader title="Rental Pricing" subtitle="Rental is priced per zone, per vehicle, as hourly packages" />

        <div className="bg-amber-50 border border-amber-200 rounded-xl p-4 flex gap-3">
          <AlertTriangle className="w-5 h-5 text-amber-600 shrink-0 mt-0.5" />
          <div className="text-sm text-amber-900">
            <p className="font-semibold">Rental does not use flat per-km pricing.</p>
            <p className="mt-1">
              Each zone defines its own packages (e.g. 4hr/40km, 8hr/80km) per vehicle, with their
              own extra-hour rate, extra-km rate, night charge and commission. Pick a zone below to
              edit them.
            </p>
          </div>
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm divide-y">
          {loading && <div className="p-6 text-center text-gray-400 text-sm">Loading zones...</div>}
          {!loading && zones.length === 0 && (
            <div className="p-6 text-center text-gray-400 text-sm">
              No zones yet — create one under <Link href="/zones" className="text-blue-600 underline">Zones</Link>.
            </div>
          )}
          {zones.map((z: any) => (
            <Link
              key={z._id}
              href={`/zones/${z._id}/pricing`}
              className="flex items-center justify-between p-4 hover:bg-gray-50"
            >
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-lg bg-blue-50 text-blue-600"><MapPin className="w-4 h-4" /></div>
                <div>
                  <div className="font-semibold text-gray-900 text-sm">{z.name}</div>
                  <div className="text-xs text-gray-500">
                    {z.city || '—'} · {(z.rentalPackages?.length ?? 0)} rental package
                    {(z.rentalPackages?.length ?? 0) === 1 ? '' : 's'}
                  </div>
                </div>
              </div>
              <span className="text-xs font-semibold text-blue-600">Edit packages →</span>
            </Link>
          ))}
        </div>
      </div>
    </div>
  )
}

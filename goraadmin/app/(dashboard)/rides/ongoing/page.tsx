'use client'
import { useState, useEffect, useCallback } from 'react'
import Link from 'next/link'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { LiveRidesMap, STATUS_COLOR, STUCK_COLOR, isStuck } from '@/components/rides/live-rides-map'
import { fmtIST, elapsed, rideHref, label } from '@/components/rides/format'
import { RefreshCw, Clock, Maximize2, AlertTriangle } from 'lucide-react'

const POLL_MS = 12_000

export default function OngoingRidesPage() {
  const [data, setData] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null)
  const [showPending, setShowPending] = useState(false)
  const [showIdle, setShowIdle] = useState(false)
  const [stuckOnly, setStuckOnly] = useState(false)
  const [fitKey, setFitKey] = useState(0)

  const fetchRides = useCallback(() => {
    const p = new URLSearchParams({ limit: '200' })
    if (showPending) p.set('pending', '1')
    if (showIdle) p.set('idle', '1')
    fetch(`/api/rides/ongoing?${p}`)
      .then(async r => { const d = await r.json().catch(() => ({})); if (!r.ok) throw new Error(d?.error || `Failed (${r.status})`); return d })
      .then(d => { setData(d); setError(''); setLastRefresh(new Date()) })
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }, [showPending, showIdle])

  useEffect(() => {
    fetchRides()
    const interval = setInterval(fetchRides, POLL_MS)
    return () => clearInterval(interval)
  }, [fetchRides])

  const rides: any[] = data?.rides || []
  const stuckN = rides.filter(isStuck).length
  const shown = stuckOnly ? rides.filter(isStuck) : rides
  const drivers = data?.drivers || {}

  return (
    <div>
      <Header title="Ongoing Rides" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="Ongoing Rides"
          subtitle={`${data?.total ?? '…'} rides active${stuckN ? ` · ${stuckN} with no driver location for 10+ min` : ''} · refreshes every ${POLL_MS / 1000} s${lastRefresh ? ` · last ${lastRefresh.toLocaleTimeString('en-IN', { timeZone: 'Asia/Kolkata' })}` : ''}`}
          action={
            <div className="flex gap-2">
              <button type="button" onClick={() => setFitKey(k => k + 1)}
                className="flex items-center gap-2 px-3 py-2 bg-white text-gray-700 rounded-lg text-sm font-medium hover:bg-gray-50 border border-gray-200">
                <Maximize2 className="w-4 h-4" /> Fit map
              </button>
              <button type="button" onClick={fetchRides}
                className="flex items-center gap-2 px-4 py-2 bg-blue-50 text-blue-600 rounded-lg text-sm font-medium hover:bg-blue-100 border border-blue-200">
                <RefreshCw className="w-4 h-4" /> Refresh
              </button>
            </div>
          }
        />

        <div className="flex flex-wrap items-center gap-4 text-sm">
          {(['accepted', 'arrived', 'ongoing', ...(showPending ? ['pending'] : [])]).map(s => (
            <span key={s} className="flex items-center gap-1.5 capitalize"><span className="w-3 h-3 rounded-full" style={{ background: STATUS_COLOR[s] }} />{label(s)}</span>
          ))}
          <span className="flex items-center gap-1.5"><span className="w-3 h-3 rounded-full" style={{ background: STUCK_COLOR }} />stuck (no location 10+ min)</span>
          <span className="text-gray-400">P pickup · D drop · arrow = driver</span>
          <label className="flex items-center gap-1.5 ml-auto"><input type="checkbox" checked={showPending} onChange={e => setShowPending(e.target.checked)} /> Include requests looking for a driver</label>
          <label className="flex items-center gap-1.5"><input type="checkbox" checked={showIdle} onChange={e => setShowIdle(e.target.checked)} /> Show idle online drivers</label>
          <label className="flex items-center gap-1.5"><input type="checkbox" checked={stuckOnly} onChange={e => setStuckOnly(e.target.checked)} /> Stuck only</label>
        </div>

        {error && <p className="text-sm text-red-600 bg-red-50 border border-red-200 rounded-lg px-3 py-2">{error}</p>}
        <LiveRidesMap data={data} fitKey={fitKey} />

        {loading ? (
          <div className="flex items-center justify-center py-12">
            <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
          </div>
        ) : shown.length === 0 ? (
          <div className="bg-white rounded-xl border border-gray-100 p-12 text-center">
            <p className="text-gray-500">{stuckOnly ? 'No stuck rides.' : 'No rides are currently ongoing.'}</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            {shown.map(r => {
              const stuck = isStuck(r)
              const d = r.driverId ? drivers[String(r.driverId)] : null
              return (
                <Link key={r._id} href={rideHref(r._id)} className={`block bg-white rounded-xl border shadow-sm p-5 hover:shadow-md transition ${stuck ? 'border-red-300 ring-1 ring-red-200' : 'border-blue-100'}`}>
                  <div className="flex items-center justify-between mb-3">
                    <span className="text-xs font-mono text-blue-600 font-bold">{String(r._id).slice(-8)}</span>
                    <span className="flex items-center gap-1 text-xs px-2 py-1 rounded-full capitalize" style={{ color: stuck ? STUCK_COLOR : STATUS_COLOR[r.status], background: '#f8fafc' }}>
                      <span className="w-1.5 h-1.5 rounded-full animate-pulse" style={{ background: stuck ? STUCK_COLOR : STATUS_COLOR[r.status] }} />
                      {label(r.status)}
                    </span>
                  </div>
                  {stuck && (
                    <p className="mb-2 text-xs font-semibold text-red-600 flex items-center gap-1"><AlertTriangle className="w-3.5 h-3.5" />
                      {r.locationStale ? `No driver location ${d?.at ? `for ${elapsed(d.at)}` : 'ever'}` : `Stuck since ${fmtIST(r.stuckSince)}`}
                    </p>
                  )}
                  <div className="space-y-2 text-sm">
                    <Row k="Rider" v={r.riderName || '—'} />
                    <Row k="Driver" v={r.driverName || '—'} />
                    <Row k="From" v={<span className="text-xs">{r.pickupAddress}</span>} />
                    <Row k="To" v={<span className="text-xs">{r.dropAddress}</span>} />
                    <Row k="Fare" v={<span className="font-semibold">₹{r.fare}</span>} />
                    <Row k="Service" v={<span className="capitalize">{label(r.service || 'taxi')}</span>} />
                  </div>
                  <div className="mt-3 pt-3 border-t border-gray-100 flex items-center gap-1 text-xs text-gray-500">
                    <Clock className="w-3.5 h-3.5" />
                    <span>{r.startedAt ? `On trip ${elapsed(r.startedAt)} (since ${fmtIST(r.startedAt)})` : r.acceptedAt ? `Accepted ${elapsed(r.acceptedAt)} ago` : `Booked ${elapsed(r.createdAt)} ago`}</span>
                  </div>
                </Link>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}

function Row({ k, v }: { k: string; v: any }) {
  return <div className="flex justify-between gap-3"><span className="text-gray-500">{k}</span><span className="text-gray-800 text-right">{v}</span></div>
}

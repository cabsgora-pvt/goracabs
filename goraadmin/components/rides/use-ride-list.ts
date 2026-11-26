'use client'
import { useEffect, useState } from 'react'

// One page of GET /api/rides (with &stats=1) for the per-service ride lists.
// `params` are the filters; changing them goes back to page 1.
export function useRideList(params: Record<string, string | undefined>, limit = 50) {
  const [rides, setRides] = useState<any[]>([])
  const [total, setTotal] = useState(0)
  const [stats, setStats] = useState<any>(null)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const key = JSON.stringify(params)
  useEffect(() => { setPage(1) }, [key])
  useEffect(() => {
    const p = new URLSearchParams({ page: String(page), limit: String(limit), stats: '1' })
    for (const [k, v] of Object.entries(JSON.parse(key) as Record<string, string>)) if (v && v !== 'all') p.set(k, v)
    let gone = false
    setLoading(true); setError('')
    fetch(`/api/rides?${p}`)
      .then(async r => { const d = await r.json().catch(() => ({})); if (!r.ok) throw new Error(d?.error || `Failed (${r.status})`); return d })
      .then(d => { if (gone) return; setRides(d.rides || []); setTotal(d.total || 0); setStats(d.stats || null) })
      .catch(e => { if (!gone) { setError(e.message); setRides([]); setTotal(0) } })
      .finally(() => { if (!gone) setLoading(false) })
    return () => { gone = true }
  }, [key, page, limit])
  return { rides, total, stats, page, setPage, loading, error, limit }
}

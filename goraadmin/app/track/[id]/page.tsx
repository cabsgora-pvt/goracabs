'use client'
import { useEffect, useState } from 'react'
import { useParams } from 'next/navigation'

type Ride = {
  id: string
  riderName: string
  pickupAddress: string
  dropAddress: string
  pickupLat: number
  pickupLng: number
  dropLat: number
  dropLng: number
  routePolyline: string
  status: string
}
type Driver = {
  name: string
  vehicleModel: string
  lat: number | null
  lng: number | null
  heading: number
  updatedAt: string | null
} | null

declare global { interface Window { google: any; initTrackMap: () => void } }

export default function TrackPage() {
  const { id } = useParams()
  const [ride, setRide] = useState<Ride | null>(null)
  const [driver, setDriver] = useState<Driver>(null)
  const [error, setError] = useState('')

  // Load Google Maps JS once
  useEffect(() => {
    if (window.google?.maps) return
    const s = document.createElement('script')
    fetch('/api/settings/maps-key')
      .then(r => r.json())
      .then(d => {
        const key = d.key || ''
        s.src = `https://maps.googleapis.com/maps/api/js?key=${key}&libraries=geometry`
        s.async = true
        document.head.appendChild(s)
      })
  }, [])

  // Fetch ride + driver every 5s
  useEffect(() => {
    let cancelled = false
    const tick = async () => {
      try {
        const r = await fetch(`/api/rides/track/${id}`).then(x => x.json())
        if (cancelled) return
        if (r.error) { setError(r.error); return }
        setRide(r.ride)
        setDriver(r.driver)
      } catch (e: any) { if (!cancelled) setError(e.message) }
    }
    tick()
    const t = setInterval(tick, 5000)
    return () => { cancelled = true; clearInterval(t) }
  }, [id])

  // Draw / update map
  useEffect(() => {
    if (!ride || !window.google?.maps) return
    const g = window.google.maps
    const el = document.getElementById('track-map')
    if (!el) return

    const w: any = window
    let map = w.__trackMap
    if (!map) {
      map = new g.Map(el, { zoom: 13, center: { lat: ride.pickupLat, lng: ride.pickupLng }, disableDefaultUI: true, zoomControl: true })
      w.__trackMap = map
    }

    // Markers
    if (!w.__pickupMarker) {
      w.__pickupMarker = new g.Marker({ position: { lat: ride.pickupLat, lng: ride.pickupLng }, map, label: 'P', title: ride.pickupAddress })
    }
    if (!w.__dropMarker) {
      w.__dropMarker = new g.Marker({ position: { lat: ride.dropLat, lng: ride.dropLng }, map, label: 'D', title: ride.dropAddress })
    }

    // Polyline (decoded once)
    if (ride.routePolyline && !w.__route) {
      const path = g.geometry.encoding.decodePath(ride.routePolyline)
      w.__route = new g.Polyline({ path, strokeColor: '#1976D2', strokeWeight: 5, strokeOpacity: 0.85, map })
    }

    // Driver marker
    if (driver?.lat != null && driver.lng != null) {
      const pos = { lat: driver.lat, lng: driver.lng }
      if (!w.__driverMarker) {
        w.__driverMarker = new g.Marker({
          position: pos, map,
          icon: { path: g.SymbolPath.FORWARD_CLOSED_ARROW, scale: 5, strokeColor: '#00C853', fillColor: '#00C853', fillOpacity: 1, rotation: driver.heading || 0 },
        })
      } else {
        w.__driverMarker.setPosition(pos)
        w.__driverMarker.setIcon({ path: g.SymbolPath.FORWARD_CLOSED_ARROW, scale: 5, strokeColor: '#00C853', fillColor: '#00C853', fillOpacity: 1, rotation: driver.heading || 0 })
      }
    }

    // Fit bounds to whatever we have
    const b = new g.LatLngBounds()
    b.extend({ lat: ride.pickupLat, lng: ride.pickupLng })
    b.extend({ lat: ride.dropLat, lng: ride.dropLng })
    if (driver?.lat != null && driver.lng != null) b.extend({ lat: driver.lat, lng: driver.lng })
    map.fitBounds(b, 60)
  }, [ride, driver])

  if (error) return <div style={{ padding: 24, fontFamily: 'Inter, sans-serif' }}>Error: {error}</div>
  if (!ride) return <div style={{ padding: 24, fontFamily: 'Inter, sans-serif' }}>Loading trip…</div>

  return (
    <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', fontFamily: 'Inter, sans-serif' }}>
      <div style={{ padding: '14px 20px', background: '#1976D2', color: 'white' }}>
        <div style={{ fontSize: 12, opacity: 0.85 }}>Live trip — Gora Cabs</div>
        <div style={{ fontWeight: 700, fontSize: 16 }}>{ride.riderName} is on a ride</div>
        <div style={{ fontSize: 13, opacity: 0.9, marginTop: 2 }}>Status: <b style={{ textTransform: 'capitalize' }}>{ride.status}</b></div>
      </div>
      <div id="track-map" style={{ flex: 1, minHeight: 360 }} />
      <div style={{ padding: 16, background: 'white', borderTop: '1px solid #eee' }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10, marginBottom: 8 }}>
          <div style={{ width: 10, height: 10, borderRadius: 99, background: '#1976D2', marginTop: 6 }} />
          <div><div style={{ fontSize: 12, color: '#666' }}>Pickup</div><div style={{ fontWeight: 600 }}>{ride.pickupAddress}</div></div>
        </div>
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10 }}>
          <div style={{ width: 10, height: 10, borderRadius: 99, background: '#E53935', marginTop: 6 }} />
          <div><div style={{ fontSize: 12, color: '#666' }}>Drop</div><div style={{ fontWeight: 600 }}>{ride.dropAddress}</div></div>
        </div>
        {driver && (
          <div style={{ marginTop: 12, padding: 12, background: '#F5F5F5', borderRadius: 10 }}>
            <div style={{ fontSize: 12, color: '#666' }}>Driver</div>
            <div style={{ fontWeight: 600 }}>{driver.name} {driver.vehicleModel ? `• ${driver.vehicleModel}` : ''}</div>
          </div>
        )}
      </div>
    </div>
  )
}

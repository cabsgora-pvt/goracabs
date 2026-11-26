'use client'
import { useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { GoogleMap, LoadScript, Marker, InfoWindow, Polyline } from '@react-google-maps/api'
import { fmtIST, elapsed, rideHref, label } from './format'

// Live map of rides under way (the admin's version of the zone panel's live
// map, app/zone-panel/(panel)/live). Real pickup / drop points, each ride's
// driver at its last reported position (Driver.currentLat/Lng), colours by
// status, a "stuck" highlight for a driver silent 10+ min, and an InfoWindow
// that links to the ride detail page. The browser key comes from
// /api/settings/maps-key (never the server key).

export const STATUS_COLOR: Record<string, string> = { pending: '#f7b84b', accepted: '#299cdb', arrived: '#7c3aed', ongoing: '#0ab39c' }
export const STUCK_COLOR = '#dc2626'
const DEFAULT_CENTER = { lat: 22.3, lng: 70.8 }

export type LiveData = { rides: any[]; drivers: Record<string, any>; idleDrivers?: any[] }

export function isStuck(r: any) { return !!r.locationStale || !!r.stuckSince }

export function LiveRidesMap({ data, height = 460, fitKey }: { data: LiveData | null; height?: number; fitKey?: number }) {
  const [key, setKey] = useState<string | null>(null)
  const [sel, setSel] = useState<any>(null)
  const mapRef = useRef<google.maps.Map | null>(null)
  const fitted = useRef(false)

  useEffect(() => { fetch('/api/settings/maps-key').then(r => r.json()).then(x => setKey(x.key || '')).catch(() => setKey('')) }, [])

  const rides = data?.rides || []
  const drivers = data?.drivers || {}
  const driverPos = (r: any) => {
    const d = r.driverId ? drivers[String(r.driverId)] : null
    return d && d.lat != null && d.lng != null ? { lat: d.lat, lng: d.lng, at: d.at } : null
  }

  const fit = () => {
    const map = mapRef.current
    if (!map || typeof google === 'undefined') return
    const b = new google.maps.LatLngBounds()
    let n = 0
    for (const r of rides) {
      if (r.pickupLat != null) { b.extend({ lat: r.pickupLat, lng: r.pickupLng }); n++ }
      if (r.dropLat != null) { b.extend({ lat: r.dropLat, lng: r.dropLng }); n++ }
      const p = driverPos(r); if (p) { b.extend(p); n++ }
    }
    if (n === 0) return
    if (n === 1) { map.setCenter(b.getCenter()); map.setZoom(14) } else map.fitBounds(b, 48)
    fitted.current = true
  }
  // Fit once when rides first arrive, and whenever the parent asks (fitKey).
  useEffect(() => { if (!fitted.current && rides.length) fit() }, [rides.length]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (fitKey) fit() }, [fitKey]) // eslint-disable-line react-hooks/exhaustive-deps

  const selRide = sel?.kind === 'ride' || sel?.kind === 'driver' ? rides.find(r => String(r._id) === String(sel.rideId)) : null
  const selDriver = selRide ? driverPos(selRide) : null

  return (
    <div className="bg-white rounded-xl border border-gray-200 overflow-hidden" style={{ height }}>
      {key === null ? <p className="p-6 text-gray-400">Loading map…</p> : !key ? (
        <p className="p-6 text-red-600">Google Maps browser key is not set (Settings → Maps → JavaScript API key).</p>
      ) : (
        <LoadScript googleMapsApiKey={key}>
          <GoogleMap mapContainerStyle={{ width: '100%', height: '100%' }} center={DEFAULT_CENTER} zoom={11}
            onLoad={m => { mapRef.current = m; if (rides.length) fit() }} onUnmount={() => { mapRef.current = null }}
            options={{ streetViewControl: false, mapTypeControl: false }}>
            {(data?.idleDrivers || []).map((x: any) => (
              <Marker key={`idle-${x._id}`} position={{ lat: x.currentLat, lng: x.currentLng }} title={`${x.name} (idle)`}
                icon={{ path: 0, scale: 4, fillColor: '#94a3b8', fillOpacity: 0.9, strokeColor: '#fff', strokeWeight: 1 }} />
            ))}
            {rides.map(r => {
              const stuck = isStuck(r)
              const color = stuck ? STUCK_COLOR : STATUS_COLOR[r.status] || '#878a99'
              const p = driverPos(r)
              return (
                <span key={r._id}>
                  {r.pickupLat != null && (
                    <Marker position={{ lat: r.pickupLat, lng: r.pickupLng }} label={{ text: 'P', color: '#fff', fontSize: '10px', fontWeight: '700' }}
                      icon={{ path: 0, scale: 9, fillColor: color, fillOpacity: 0.95, strokeColor: '#fff', strokeWeight: 1.5 }}
                      onClick={() => setSel({ kind: 'ride', rideId: r._id, pos: { lat: r.pickupLat, lng: r.pickupLng } })} />
                  )}
                  {r.dropLat != null && (
                    <Marker position={{ lat: r.dropLat, lng: r.dropLng }} label={{ text: 'D', color: '#fff', fontSize: '10px', fontWeight: '700' }}
                      icon={{ path: 0, scale: 8, fillColor: '#475569', fillOpacity: 0.85, strokeColor: '#fff', strokeWeight: 1.5 }}
                      onClick={() => setSel({ kind: 'ride', rideId: r._id, pos: { lat: r.dropLat, lng: r.dropLng } })} />
                  )}
                  {p && (
                    <Marker position={p} title={`${r.driverName || 'Driver'}${stuck ? ' — no location for 10+ min' : ''}`}
                      icon={{ path: 1, scale: 5, rotation: drivers[String(r.driverId)]?.heading || 0, fillColor: color, fillOpacity: 1, strokeColor: '#111827', strokeWeight: 1 }}
                      onClick={() => setSel({ kind: 'driver', rideId: r._id, pos: p })} />
                  )}
                </span>
              )
            })}
            {selRide && selRide.pickupLat != null && selRide.dropLat != null && (
              <Polyline path={[{ lat: selRide.pickupLat, lng: selRide.pickupLng }, { lat: selRide.dropLat, lng: selRide.dropLng }]}
                options={{ strokeColor: '#405189', strokeOpacity: 0.7, strokeWeight: 3, geodesic: true }} />
            )}
            {selRide && selDriver && selRide.pickupLat != null && ['accepted', 'arrived'].includes(selRide.status) && (
              <Polyline path={[selDriver, { lat: selRide.pickupLat, lng: selRide.pickupLng }]}
                options={{ strokeColor: '#299cdb', strokeOpacity: 0.6, strokeWeight: 2 }} />
            )}
            {sel && selRide && (
              <InfoWindow position={sel.pos} onCloseClick={() => setSel(null)}>
                <div className="text-[12.5px] max-w-[260px] space-y-0.5">
                  <p className="font-semibold capitalize">{label(selRide.status)} · {label(selRide.service || 'taxi')} · {selRide.vehicleType}</p>
                  <p>Rider: {selRide.riderName || '—'}{selRide.driverName ? ` · Driver: ${selRide.driverName}` : ''}</p>
                  <p className="text-gray-500">{selRide.pickupAddress} → {selRide.dropAddress}</p>
                  <p className="text-gray-500">{selRide.startedAt ? `On trip ${elapsed(selRide.startedAt)}` : selRide.acceptedAt ? `Accepted ${elapsed(selRide.acceptedAt)} ago` : `Booked ${elapsed(selRide.createdAt)} ago`}</p>
                  {isStuck(selRide) && <p className="text-red-600 font-semibold">{selRide.locationStale ? `No driver location since ${selDriver?.at ? fmtIST(selDriver.at) : 'ever'}` : `Stuck since ${fmtIST(selRide.stuckSince)}`}</p>}
                  <Link href={rideHref(selRide._id)} className="text-blue-600 hover:underline font-semibold">Open ride →</Link>
                </div>
              </InfoWindow>
            )}
          </GoogleMap>
        </LoadScript>
      )}
    </div>
  )
}

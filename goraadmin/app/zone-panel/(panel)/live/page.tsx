'use client'
import { useEffect, useState } from 'react'
import { GoogleMap, LoadScript, Marker, Polygon, InfoWindow } from '@react-google-maps/api'
import { Header } from '@/components/header'
import { zoneFetch } from '@/components/zone-shell'

const STATUS_COLOR: Record<string, string> = { pending: '#f7b84b', accepted: '#299cdb', arrived: '#299cdb', ongoing: '#0ab39c' }

// Online drivers and rides under way in the zone admin's zones, refreshed
// every 15 seconds.
export default function ZoneLiveMap() {
  const [key, setKey] = useState<string | null>(null)
  const [d, setD] = useState<any>(null)
  const [sel, setSel] = useState<any>(null)

  useEffect(() => { fetch('/api/settings/maps-key').then(r => r.json()).then(x => setKey(x.key || '')).catch(() => setKey('')) }, [])
  useEffect(() => {
    const load = () => zoneFetch('/api/zone-admin/live').then(r => r.json()).then(setD).catch(() => {})
    load()
    const t = setInterval(load, 15000)
    return () => clearInterval(t)
  }, [])

  const z0 = d?.zones?.[0]
  const center = z0 ? { lat: z0.centerLat, lng: z0.centerLng } : { lat: 22.3, lng: 70.8 }

  return (
    <div>
      <Header title="Live Map" />
      <div className="p-6 space-y-3">
        <div className="flex flex-wrap gap-4 text-[13px]">
          <span><b>{d?.drivers?.length ?? '…'}</b> drivers online</span>
          <span><b>{d?.rides?.length ?? '…'}</b> rides open or under way</span>
          <span className="text-gray-400">Refreshes every 15 s</span>
        </div>
        <div className="bg-white rounded shadow-sm overflow-hidden" style={{ height: 'calc(100vh - 230px)', minHeight: 420 }}>
          {key === null ? <p className="p-6 text-gray-400">Loading map…</p> : !key ? <p className="p-6 text-red-600">Map key not set. Ask Gora.</p> : (
            <LoadScript googleMapsApiKey={key}>
              <GoogleMap mapContainerStyle={{ width: '100%', height: '100%' }} center={center} zoom={12}
                options={{ streetViewControl: false, mapTypeControl: false }}>
                {(d?.zones || []).map((z: any) => z.polygonPath?.length > 2 && (
                  <Polygon key={z._id} paths={z.polygonPath} options={{ fillColor: '#405189', fillOpacity: 0.06, strokeColor: '#405189', strokeWeight: 2 }} />
                ))}
                {(d?.drivers || []).map((x: any) => (
                  <Marker key={x._id} position={{ lat: x.currentLat, lng: x.currentLng }}
                    icon={{ path: 0, scale: 7, fillColor: '#0ab39c', fillOpacity: 1, strokeColor: '#fff', strokeWeight: 2 }}
                    onClick={() => setSel({ kind: 'driver', ...x, pos: { lat: x.currentLat, lng: x.currentLng } })} />
                ))}
                {(d?.rides || []).filter((r: any) => r.pickupLat != null).map((r: any) => (
                  <Marker key={r._id} position={{ lat: r.pickupLat, lng: r.pickupLng }}
                    icon={{ path: 1, scale: 5, fillColor: STATUS_COLOR[r.status] || '#878a99', fillOpacity: 1, strokeColor: '#fff', strokeWeight: 1.5 }}
                    onClick={() => setSel({ kind: 'ride', ...r, pos: { lat: r.pickupLat, lng: r.pickupLng } })} />
                ))}
                {sel && (
                  <InfoWindow position={sel.pos} onCloseClick={() => setSel(null)}>
                    {sel.kind === 'driver' ? (
                      <div className="text-[12.5px]">
                        <p className="font-semibold">{sel.name}</p>
                        <p>{sel.selectedVehicleTypeName} {sel.vehicleNumber ? `· ${sel.vehicleNumber}` : ''}</p>
                        <p className="text-gray-500">{sel.phone}</p>
                      </div>
                    ) : (
                      <div className="text-[12.5px] max-w-[240px]">
                        <p className="font-semibold capitalize">{sel.status} · {(sel.service || 'taxi').replace('_', ' ')} · {sel.vehicleType}</p>
                        <p>Rider: {sel.riderName || '—'}{sel.driverName ? ` · Driver: ${sel.driverName}` : ''}</p>
                        <p className="text-gray-500">{sel.pickupAddress} → {sel.dropAddress}</p>
                      </div>
                    )}
                  </InfoWindow>
                )}
              </GoogleMap>
            </LoadScript>
          )}
        </div>
        <p className="text-xs text-gray-500">Green dots: online drivers. Arrows: ride pickups — amber waiting for a driver, blue driver on the way, green trip under way.</p>
      </div>
    </div>
  )
}

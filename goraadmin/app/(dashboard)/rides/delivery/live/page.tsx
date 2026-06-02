'use client'
import { useState, useEffect } from 'react'
import { GoogleMap, LoadScript, Marker, InfoWindow } from '@react-google-maps/api'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'

const API_KEY = 'AIzaSyBUVrSVVulUrs5MZBwW0yLBFByA9Q_HwC4'
const CENTER = { lat: 26.2389, lng: 73.0243 } // Jodhpur-ish default

export default function LiveDeliveriesPage() {
  const [deliveries, setDeliveries] = useState<any[]>([])
  const [sel, setSel] = useState<any>(null)

  const fetch_ = () => {
    fetch('/api/rides/delivery/active').then(r => r.json()).then(d => setDeliveries(d.deliveries || [])).catch(() => {})
  }
  useEffect(() => { fetch_(); const t = setInterval(fetch_, 8000); return () => clearInterval(t) }, [])

  const withDriver = deliveries.filter(d => d.driverLat != null && d.driverLng != null)
  const center = withDriver[0] ? { lat: withDriver[0].driverLat, lng: withDriver[0].driverLng } : CENTER

  return (
    <div>
      <Header title="Live Deliveries" />
      <div className="p-6 space-y-4">
        <PageHeader title="Live Deliveries Map" subtitle={`${deliveries.length} active · ${withDriver.length} with live location`} />
        <div className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden" style={{ height: 560 }}>
          <LoadScript googleMapsApiKey={API_KEY}>
            <GoogleMap mapContainerStyle={{ width: '100%', height: '100%' }} center={center} zoom={12}>
              {deliveries.map(d => (
                <div key={d.id}>
                  {d.driverLat != null && (
                    <Marker position={{ lat: d.driverLat, lng: d.driverLng }} onClick={() => setSel(d)}
                      icon={{ path: 0, scale: 6, fillColor: '#0d9488', fillOpacity: 1, strokeColor: '#fff', strokeWeight: 2 }} />
                  )}
                  {d.pickupLat != null && <Marker position={{ lat: d.pickupLat, lng: d.pickupLng }} label={{ text: 'P', color: '#fff', fontSize: '11px' }} />}
                  {d.dropLat != null && <Marker position={{ lat: d.dropLat, lng: d.dropLng }} label={{ text: 'D', color: '#fff', fontSize: '11px' }} />}
                </div>
              ))}
              {sel && sel.driverLat != null && (
                <InfoWindow position={{ lat: sel.driverLat, lng: sel.driverLng }} onCloseClick={() => setSel(null)}>
                  <div className="text-xs">
                    <div className="font-bold">{sel.driverName || 'Driver'}</div>
                    <div>{sel.itemType} · {sel.deliveryPhase}</div>
                    <div>{sel.senderName} → {sel.receiverName}</div>
                    <div className="text-gray-500">{sel.vehicleNumber}</div>
                  </div>
                </InfoWindow>
              )}
            </GoogleMap>
          </LoadScript>
        </div>
        {withDriver.length === 0 && <p className="text-sm text-gray-400 text-center">No active deliveries with live location right now.</p>}
      </div>
    </div>
  )
}

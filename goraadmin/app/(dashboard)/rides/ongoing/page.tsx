'use client'
import { useState, useEffect } from 'react'
import { GoogleMap, LoadScript, Marker } from '@react-google-maps/api'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { RefreshCw, Clock } from 'lucide-react'

const JS_API_KEY = 'AIzaSyBUVrSVVulUrs5MZBwW0yLBFByA9Q_HwC4'
const MAP_CENTER = { lat: 23.0225, lng: 72.5714 }

export default function OngoingRidesPage() {
  const [rides, setRides] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [lastRefresh, setLastRefresh] = useState(new Date())

  const fetchRides = () => {
    fetch('/api/rides/ongoing')
      .then(r => r.json())
      .then(d => { setRides(d.rides || []); setLoading(false); setLastRefresh(new Date()) })
      .catch(() => setLoading(false))
  }

  useEffect(() => {
    fetchRides()
    const interval = setInterval(fetchRides, 30000)
    return () => clearInterval(interval)
  }, [])

  return (
    <div>
      <Header title="Ongoing Rides" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="Ongoing Rides"
          subtitle={`${rides.length} rides currently active`}
          action={
            <button type="button" onClick={fetchRides}
              className="flex items-center gap-2 px-4 py-2 bg-blue-50 text-blue-600 rounded-lg text-sm font-medium hover:bg-blue-100 border border-blue-200">
              <RefreshCw className="w-4 h-4" /> Refresh
            </button>
          }
        />

        <div className="rounded-xl border border-gray-200 overflow-hidden" style={{ height: 360 }}>
          <LoadScript googleMapsApiKey={JS_API_KEY}>
            <GoogleMap
              mapContainerStyle={{ width: '100%', height: '100%' }}
              center={MAP_CENTER}
              zoom={12}
            >
              {rides.map((r, i) => (
                <Marker
                  key={r._id}
                  position={{
                    lat: r.pickupLat || MAP_CENTER.lat + (i * 0.02 - 0.04),
                    lng: r.pickupLng || MAP_CENTER.lng + (i * 0.02 - 0.04),
                  }}
                  title={`${r.riderName} → ${r.driverName}`}
                />
              ))}
            </GoogleMap>
          </LoadScript>
          {rides.slice(0, 3).map((_r, i) => (
            <div key={i} className="hidden" />
          ))}
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-12">
            <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
          </div>
        ) : rides.length === 0 ? (
          <div className="bg-white rounded-xl border border-gray-100 p-12 text-center">
            <p className="text-gray-500">No rides are currently ongoing.</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            {rides.map(r => (
              <div key={r._id} className="bg-white rounded-xl border border-blue-100 shadow-sm p-5">
                <div className="flex items-center justify-between mb-3">
                  <span className="text-xs font-mono text-blue-600 font-bold">{r._id?.slice(-6)}</span>
                  <span className="flex items-center gap-1 text-xs text-blue-600 bg-blue-50 px-2 py-1 rounded-full">
                    <div className="w-1.5 h-1.5 rounded-full bg-blue-500 animate-pulse" />
                    Ongoing
                  </span>
                </div>
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-gray-500">Rider</span>
                    <span className="font-medium text-gray-800">{r.riderName || '—'}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">Driver</span>
                    <span className="font-medium text-gray-800">{r.driverName || '—'}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">From</span>
                    <span className="text-gray-700 text-xs">{r.pickupAddress}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">To</span>
                    <span className="text-gray-700 text-xs">{r.dropAddress}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">Fare</span>
                    <span className="font-semibold text-gray-800">₹{r.fare}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">Service</span>
                    <span className="text-gray-700 capitalize">{r.service}</span>
                  </div>
                </div>
                {r.startedAt && (
                  <div className="mt-3 pt-3 border-t border-gray-100 flex items-center gap-1 text-xs text-gray-400">
                    <Clock className="w-3.5 h-3.5" />
                    <span>Started at {new Date(r.startedAt).toLocaleTimeString()}</span>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

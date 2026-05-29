'use client'
import { useState, useEffect, useRef, useCallback } from 'react'
import {
  GoogleMap, LoadScript, Polygon, DrawingManager, Marker, InfoWindow
} from '@react-google-maps/api'
import { Header } from '@/components/header'
import { Toast } from '@/components/ui/toast'
import { Modal } from '@/components/ui/modal'
import { Badge } from '@/components/ui/badge'
import { Plus, Edit2, Trash2, MapPin, ToggleLeft, ToggleRight, ChevronRight } from 'lucide-react'
import Link from 'next/link'

const API_KEY = 'AIzaSyBUVrSVVulUrs5MZBwW0yLBFByA9Q_HwC4'
const LIBRARIES: ('drawing')[] = ['drawing']
const MAP_CENTER = { lat: 23.0225, lng: 72.5714 }
const ZONE_COLORS = ['#1565C0','#2E7D32','#C62828','#F57F17','#6A1B9A','#00838F','#4527A0','#AD1457']

type LatLng = { lat: number; lng: number }
type Zone = {
  _id: string; name: string; city: string; type: string;
  isActive: boolean; polygonPath: LatLng[]; centerLat: number; centerLng: number;
}

export default function ZonesPage() {
  const [zones, setZones] = useState<Zone[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [savingPeak, setSavingPeak] = useState(false)
  const [selectedZone, setSelectedZone] = useState<Zone | null>(null)
  const [peakSettings, setPeakSettings] = useState({ peakZoneRadius: 0, peakZoneDuration: 0, peakZoneRideCount: 0, distancePricePercentage: 0, maximumDistance: 0, maximumOutstationDistance: 0 })
  const [editingZone, setEditingZone] = useState<Zone | null>(null)
  const [drawnPath, setDrawnPath] = useState<LatLng[] | null>(null)
  const [drawMode, setDrawMode] = useState(false)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ name: '', city: '', type: 'city' })
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)
  const [infoPos, setInfoPos] = useState<LatLng | null>(null)
  const editPolygonRef = useRef<google.maps.Polygon | null>(null)

  const fetchZones = useCallback(() => {
    fetch('/api/zones').then(r => r.json())
      .then(d => { setZones(d.zones || []); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  useEffect(() => { fetchZones() }, [fetchZones])

  // Compute polygon center
  const getCenter = (path: LatLng[] | undefined | null) => {
    if (!path || path.length === 0) return MAP_CENTER
    const lat = path.reduce((s, p) => s + (p.lat || 0), 0) / path.length
    const lng = path.reduce((s, p) => s + (p.lng || 0), 0) / path.length
    return { lat, lng }
  }

  // Reverse geocode center to get city name automatically
  const getCityFromCoords = async (lat: number, lng: number): Promise<string> => {
    try {
      const res = await fetch(
        `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${API_KEY}`
      )
      const data = await res.json()
      const components = data.results?.[0]?.address_components || []
      const city = components.find((c: any) =>
        c.types.includes('locality') || c.types.includes('administrative_area_level_2')
      )
      return city?.long_name || ''
    } catch { return '' }
  }

  // Drawing complete — auto-detect city then show save form
  const onPolygonComplete = async (polygon: google.maps.Polygon) => {
    const path = polygon.getPath().getArray().map(p => ({ lat: p.lat(), lng: p.lng() }))
    polygon.setMap(null)
    setDrawnPath(path)
    setDrawMode(false)
    const center = getCenter(path)
    const city = await getCityFromCoords(center.lat, center.lng)
    setForm({ name: '', city, type: 'city' })
    setShowForm(true)
  }

  // Save new zone
  const saveZone = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!drawnPath || drawnPath.length < 3) {
      setToast({ msg: 'Please draw a zone boundary first', type: 'error' }); return
    }
    const center = getCenter(drawnPath)
    setSaving(true)
    const res = await fetch('/api/zones', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...form, polygonPath: drawnPath, centerLat: center.lat, centerLng: center.lng }),
    })
    setSaving(false)
    if (res.ok) {
      setShowForm(false); setDrawnPath(null)
      setToast({ msg: 'Zone created!', type: 'success' })
      fetchZones()
    }
  }

  // Update edited zone boundary
  const saveEdit = async () => {
    if (!editingZone) return
    const path = editPolygonRef.current
      ? editPolygonRef.current.getPath().getArray().map(p => ({ lat: p.lat(), lng: p.lng() }))
      : editingZone.polygonPath
    const center = getCenter(path)
    setSaving(true)
    const res = await fetch(`/api/zones/${editingZone._id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: editingZone.name, city: editingZone.city, type: editingZone.type,
        polygonPath: path, centerLat: center.lat, centerLng: center.lng,
      }),
    })
    setSaving(false)
    if (res.ok) {
      setEditingZone(null); setToast({ msg: 'Zone updated!', type: 'success' }); fetchZones()
    }
  }

  const deleteZone = async (id: string) => {
    if (!confirm('Delete this zone?')) return
    await fetch(`/api/zones/${id}`, { method: 'DELETE' })
    setSelectedZone(null)
    setToast({ msg: 'Zone deleted', type: 'success' })
    fetchZones()
  }

  const toggleZone = async (z: Zone) => {
    const res = await fetch(`/api/zones/${z._id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ isActive: !z.isActive }),
    })
    if (res.ok) {
      setZones(prev => prev.map(x => x._id === z._id ? { ...x, isActive: !x.isActive } : x))
      if (selectedZone?._id === z._id) setSelectedZone({ ...selectedZone, isActive: !z.isActive })
    }
  }

  const cancelDraw = () => { setDrawMode(false); setDrawnPath(null); setShowForm(false) }

  const savePeakSettings = async () => {
    if (!selectedZone) return
    setSavingPeak(true)
    const res = await fetch(`/api/zones/${selectedZone._id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(peakSettings),
    })
    setSavingPeak(false)
    if (res.ok) {
      setToast({ msg: 'Peak zone settings saved!', type: 'success' })
      fetchZones()
    } else {
      setToast({ msg: 'Failed to save peak settings', type: 'error' })
    }
  }

  return (
    <div className="flex flex-col h-screen overflow-hidden">
      <Header title="Zone Management" />

      <div className="flex flex-1 overflow-hidden">
        {/* ── Left sidebar: zone list ── */}
        <div className="w-80 flex-shrink-0 bg-white border-r border-gray-100 flex flex-col overflow-hidden">
          <div className="p-4 border-b border-gray-100">
            <div className="flex items-center justify-between mb-3">
              <h2 className="font-bold text-gray-900">Zones ({zones.length})</h2>
              <button
                type="button"
                onClick={() => { setDrawMode(true); setSelectedZone(null); setEditingZone(null) }}
                className="flex items-center gap-1.5 px-3 py-1.5 bg-primary text-white rounded-lg text-xs font-semibold hover:bg-primary-dark"
              >
                <Plus className="w-3.5 h-3.5" /> Draw Zone
              </button>
            </div>
            {drawMode && (
              <div className="bg-blue-50 border border-blue-200 rounded-lg p-3 text-xs text-blue-800">
                <p className="font-semibold mb-1">✏️ Drawing mode active</p>
                <p>Click on map to place points. Double-click to finish the polygon.</p>
                <button type="button" onClick={cancelDraw} className="mt-2 text-red-600 font-medium">Cancel</button>
              </div>
            )}
          </div>

          <div className="flex-1 overflow-y-auto divide-y divide-gray-50">
            {loading ? (
              <div className="flex items-center justify-center py-12">
                <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
              </div>
            ) : zones.length === 0 ? (
              <div className="text-center text-gray-400 py-12 px-4">
                <MapPin className="w-8 h-8 mx-auto mb-2 opacity-30" />
                <p>No zones yet. Draw one on the map.</p>
              </div>
            ) : zones.map((z, i) => (
              <div
                key={z._id}
                onClick={() => { setSelectedZone(z); setInfoPos({ lat: z.centerLat || MAP_CENTER.lat, lng: z.centerLng || MAP_CENTER.lng }); setPeakSettings({ peakZoneRadius: (z as any).peakZoneRadius ?? 0, peakZoneDuration: (z as any).peakZoneDuration ?? 0, peakZoneRideCount: (z as any).peakZoneRideCount ?? 0, distancePricePercentage: (z as any).distancePricePercentage ?? 0, maximumDistance: (z as any).maximumDistance ?? 0, maximumOutstationDistance: (z as any).maximumOutstationDistance ?? 0 }) }}
                className={`p-4 cursor-pointer hover:bg-gray-50 transition-colors ${selectedZone?._id === z._id ? 'bg-blue-50 border-l-4 border-blue-600' : ''}`}
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="flex items-center gap-2 min-w-0">
                    <div className="w-3 h-3 rounded-full flex-shrink-0" style={{ backgroundColor: ZONE_COLORS[i % ZONE_COLORS.length] }} />
                    <div className="min-w-0">
                      <p className="font-semibold text-gray-900 text-sm truncate">{z.name}</p>
                      <p className="text-xs text-gray-500">{z.city} · {z.type}</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-1 flex-shrink-0">
                    <Badge status={z.isActive ? 'active' : 'blocked'} />
                    <ChevronRight className="w-4 h-4 text-gray-300" />
                  </div>
                </div>
                {z.polygonPath?.length > 0 && (
                  <p className="text-xs text-gray-400 mt-1 ml-5">{z.polygonPath.length} boundary points</p>
                )}
              </div>
            ))}
          </div>
        </div>

        {/* ── Right: map + detail panel ── */}
        <div className="flex-1 flex flex-col overflow-hidden">
          {/* Map */}
          <div className="flex-1 relative">
            <LoadScript googleMapsApiKey={API_KEY} libraries={LIBRARIES}>
              <GoogleMap
                mapContainerStyle={{ width: '100%', height: '100%' }}
                center={selectedZone ? { lat: selectedZone.centerLat, lng: selectedZone.centerLng } : MAP_CENTER}
                zoom={selectedZone ? 13 : 11}
                options={{ streetViewControl: false, mapTypeControlOptions: { position: 3 } }}
              >
                {/* Drawing manager */}
                {drawMode && (
                  <DrawingManager
                    drawingMode={'polygon' as any}
                    options={{
                      drawingControl: false,
                      polygonOptions: {
                        fillColor: '#1565C0', fillOpacity: 0.25,
                        strokeColor: '#1565C0', strokeWeight: 2, editable: true,
                      },
                    }}
                    onPolygonComplete={onPolygonComplete}
                  />
                )}

                {/* Drawn but unsaved polygon */}
                {drawnPath && drawnPath.length > 2 && (
                  <Polygon
                    paths={drawnPath}
                    options={{ fillColor: '#1565C0', fillOpacity: 0.2, strokeColor: '#1565C0', strokeWeight: 2 }}
                  />
                )}

                {/* All existing zones */}
                {zones.map((z, i) => z.polygonPath?.length > 2 ? (
                  <Polygon
                    key={z._id}
                    paths={z.polygonPath}
                    options={{
                      fillColor: ZONE_COLORS[i % ZONE_COLORS.length],
                      fillOpacity: selectedZone?._id === z._id ? 0.35 : 0.15,
                      strokeColor: ZONE_COLORS[i % ZONE_COLORS.length],
                      strokeWeight: selectedZone?._id === z._id ? 3 : 1.5,
                      editable: editingZone?._id === z._id,
                      zIndex: selectedZone?._id === z._id ? 10 : 1,
                    }}
                    onLoad={p => { if (editingZone?._id === z._id) editPolygonRef.current = p }}
                    onClick={() => { setSelectedZone(z); setInfoPos({ lat: z.centerLat || MAP_CENTER.lat, lng: z.centerLng || MAP_CENTER.lng }); setPeakSettings({ peakZoneRadius: (z as any).peakZoneRadius ?? 0, peakZoneDuration: (z as any).peakZoneDuration ?? 0, peakZoneRideCount: (z as any).peakZoneRideCount ?? 0, distancePricePercentage: (z as any).distancePricePercentage ?? 0, maximumDistance: (z as any).maximumDistance ?? 0, maximumOutstationDistance: (z as any).maximumOutstationDistance ?? 0 }) }}
                  />
                ) : (
                  <Marker
                    key={z._id}
                    position={{ lat: z.centerLat, lng: z.centerLng }}
                    title={z.name}
                    onClick={() => { setSelectedZone(z); setInfoPos({ lat: z.centerLat || MAP_CENTER.lat, lng: z.centerLng || MAP_CENTER.lng }); setPeakSettings({ peakZoneRadius: (z as any).peakZoneRadius ?? 0, peakZoneDuration: (z as any).peakZoneDuration ?? 0, peakZoneRideCount: (z as any).peakZoneRideCount ?? 0, distancePricePercentage: (z as any).distancePricePercentage ?? 0, maximumDistance: (z as any).maximumDistance ?? 0, maximumOutstationDistance: (z as any).maximumOutstationDistance ?? 0 }) }}
                  />
                ))}

                {/* Info window for selected zone */}
                {selectedZone && infoPos && typeof infoPos.lat === 'number' && typeof infoPos.lng === 'number' && (
                  <InfoWindow position={{ lat: infoPos.lat, lng: infoPos.lng }} onCloseClick={() => { setSelectedZone(null); setInfoPos(null) }}>
                    <div className="text-sm min-w-32">
                      <p className="font-bold text-gray-900">{selectedZone.name}</p>
                      <p className="text-gray-500 text-xs">{selectedZone.city} · {selectedZone.type}</p>
                      <p className={`text-xs font-medium mt-1 ${selectedZone.isActive ? 'text-green-600' : 'text-red-500'}`}>
                        {selectedZone.isActive ? '● Active' : '● Inactive'}
                      </p>
                    </div>
                  </InfoWindow>
                )}
              </GoogleMap>
            </LoadScript>

            {/* Draw mode overlay hint */}
            {drawMode && (
              <div className="absolute top-4 left-1/2 -translate-x-1/2 bg-white shadow-lg rounded-full px-4 py-2 text-sm font-medium text-blue-700 border border-blue-200 pointer-events-none">
                Click to add points · Double-click to finish
              </div>
            )}
          </div>

          {/* Zone detail panel (shown when zone selected) */}
          {selectedZone && !editingZone && (
            <div className="bg-white border-t border-gray-100 overflow-y-auto max-h-80">
              <div className="p-4 flex items-center justify-between border-b border-gray-50">
                <div>
                  <h3 className="font-bold text-gray-900 text-lg">{selectedZone.name}</h3>
                  <p className="text-sm text-gray-500">{selectedZone.city} · {selectedZone.type} · {selectedZone.polygonPath?.length || 0} boundary points</p>
                </div>
                <div className="flex items-center gap-2">
                  <Link href={`/zones/${selectedZone._id}/pricing`}
                    className="px-3 py-1.5 bg-blue-50 text-blue-600 rounded-lg text-sm font-medium hover:bg-blue-100 border border-blue-200">
                    Set Pricing
                  </Link>
                  <button type="button" onClick={() => toggleZone(selectedZone)}
                    className="p-2 hover:bg-gray-100 rounded-lg text-gray-600" title="Toggle active">
                    {selectedZone.isActive ? <ToggleRight className="w-5 h-5 text-green-600" /> : <ToggleLeft className="w-5 h-5 text-gray-400" />}
                  </button>
                  <button type="button" onClick={() => setEditingZone(selectedZone)}
                    className="p-2 hover:bg-blue-50 rounded-lg text-blue-600" title="Edit zone">
                    <Edit2 className="w-5 h-5" />
                  </button>
                  <button type="button" onClick={() => deleteZone(selectedZone._id)}
                    className="p-2 hover:bg-red-50 rounded-lg text-red-500" title="Delete zone">
                    <Trash2 className="w-5 h-5" />
                  </button>
                </div>
              </div>
              {/* Peak Zone Settings */}
              <div className="p-4">
                <h4 className="text-sm font-semibold text-gray-700 mb-3">Peak Zone Settings</h4>
                <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
                  <div>
                    <label htmlFor="peak-radius" className="block text-xs font-medium text-gray-600 mb-1">Peak Zone Radius (m)</label>
                    <input id="peak-radius" type="number" title="Peak zone radius in metres" value={peakSettings.peakZoneRadius}
                      onChange={e => setPeakSettings({ ...peakSettings, peakZoneRadius: +e.target.value })}
                      className="w-full border border-gray-300 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                  </div>
                  <div>
                    <label htmlFor="peak-duration" className="block text-xs font-medium text-gray-600 mb-1">Peak Zone Duration (min)</label>
                    <input id="peak-duration" type="number" title="Peak zone duration in minutes" value={peakSettings.peakZoneDuration}
                      onChange={e => setPeakSettings({ ...peakSettings, peakZoneDuration: +e.target.value })}
                      className="w-full border border-gray-300 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                  </div>
                  <div>
                    <label htmlFor="peak-ride-count" className="block text-xs font-medium text-gray-600 mb-1">Peak Zone Ride Count</label>
                    <input id="peak-ride-count" type="number" title="Number of rides to trigger peak surge" value={peakSettings.peakZoneRideCount}
                      onChange={e => setPeakSettings({ ...peakSettings, peakZoneRideCount: +e.target.value })}
                      className="w-full border border-gray-300 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                  </div>
                  <div>
                    <label htmlFor="peak-surge-pct" className="block text-xs font-medium text-gray-600 mb-1">Distance Price % (surge)</label>
                    <input id="peak-surge-pct" type="number" title="Surge percentage applied to distance price" value={peakSettings.distancePricePercentage}
                      onChange={e => setPeakSettings({ ...peakSettings, distancePricePercentage: +e.target.value })}
                      className="w-full border border-gray-300 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                  </div>
                  <div>
                    <label htmlFor="peak-max-dist" className="block text-xs font-medium text-gray-600 mb-1">Max Ride Distance (km)</label>
                    <input id="peak-max-dist" type="number" title="Maximum ride distance in km (0 = unlimited)" value={peakSettings.maximumDistance}
                      onChange={e => setPeakSettings({ ...peakSettings, maximumDistance: +e.target.value })}
                      className="w-full border border-gray-300 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                  </div>
                  <div>
                    <label htmlFor="peak-max-outstation" className="block text-xs font-medium text-gray-600 mb-1">Max Outstation Distance (km)</label>
                    <input id="peak-max-outstation" type="number" title="Maximum outstation distance in km (0 = unlimited)" value={peakSettings.maximumOutstationDistance}
                      onChange={e => setPeakSettings({ ...peakSettings, maximumOutstationDistance: +e.target.value })}
                      className="w-full border border-gray-300 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                  </div>
                </div>
                <div className="mt-3 flex justify-end">
                  <button type="button" onClick={savePeakSettings} disabled={savingPeak}
                    className="px-5 py-2 bg-primary text-white rounded-lg text-sm font-semibold hover:bg-primary-dark disabled:opacity-60">
                    {savingPeak ? 'Saving...' : 'Save Peak Settings'}
                  </button>
                </div>
              </div>
            </div>
          )}

          {/* Edit panel */}
          {editingZone && (
            <div className="bg-white border-t border-gray-100 p-4">
              <div className="flex items-center gap-4">
                <div className="flex gap-3 flex-1">
                  <input value={editingZone.name} onChange={e => setEditingZone({ ...editingZone, name: e.target.value })}
                    className="border border-gray-300 rounded-lg px-3 py-2 text-sm flex-1" placeholder="Zone name" />
                  <input value={editingZone.city} onChange={e => setEditingZone({ ...editingZone, city: e.target.value })}
                    className="border border-gray-300 rounded-lg px-3 py-2 text-sm flex-1" placeholder="City" />
                  <select title="Zone type" value={editingZone.type} onChange={e => setEditingZone({ ...editingZone, type: e.target.value })}
                    className="border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white">
                    <option value="city">City</option>
                    <option value="airport">Airport</option>
                    <option value="outskirts">Outskirts</option>
                    <option value="industrial">Industrial</option>
                    <option value="ithub">IT Hub</option>
                  </select>
                </div>
                <p className="text-xs text-blue-600 flex-shrink-0">Drag polygon points to reshape</p>
                <div className="flex gap-2">
                  <button type="button" onClick={() => setEditingZone(null)}
                    className="px-4 py-2 border border-gray-300 text-gray-700 rounded-lg text-sm">Cancel</button>
                  <button type="button" onClick={saveEdit} disabled={saving}
                    className="px-4 py-2 bg-primary text-white rounded-lg text-sm font-semibold hover:bg-primary-dark disabled:opacity-60">
                    {saving ? 'Saving...' : 'Save Changes'}
                  </button>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* New zone form modal */}
      {showForm && (
        <Modal title="Name Your Zone" onClose={cancelDraw}>
          <form onSubmit={saveZone} className="space-y-4">
            <div className="bg-blue-50 rounded-lg px-3 py-2 text-xs text-blue-700">
              Zone boundary drawn with {drawnPath?.length} points
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Zone Name *</label>
              <input required value={form.name} onChange={e => setForm({ ...form, name: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm" placeholder="e.g. Airport Zone" />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">City *</label>
              <input required value={form.city} onChange={e => setForm({ ...form, city: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm" placeholder="e.g. Ahmedabad" />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Zone Type</label>
              <select title="Zone type" value={form.type} onChange={e => setForm({ ...form, type: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white">
                <option value="city">City</option>
                <option value="airport">Airport</option>
                <option value="outskirts">Outskirts</option>
                <option value="industrial">Industrial</option>
                <option value="ithub">IT Hub</option>
              </select>
            </div>
            <div className="flex gap-3 pt-2">
              <button type="button" onClick={cancelDraw}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm">Cancel</button>
              <button type="submit" disabled={saving}
                className="flex-1 bg-primary text-white rounded-lg py-2 text-sm font-semibold disabled:opacity-60">
                {saving ? 'Saving...' : 'Create Zone'}
              </button>
            </div>
          </form>
        </Modal>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}

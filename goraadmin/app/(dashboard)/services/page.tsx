'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Toast } from '@/components/ui/toast'
import { Car, Clock, Map, Package, Truck, UserCheck, ArrowRight } from 'lucide-react'
import Link from 'next/link'

const servicesList = [
  { id: 'taxi',        label: 'Taxi',          icon: Car,       description: 'Point-to-point city rides',      href: '/services/taxi',        color: 'bg-blue-50 text-blue-600' },
  { id: 'rental',      label: 'Rental',        icon: Clock,     description: 'Hourly car rental packages',     href: '/services/rental',      color: 'bg-green-50 text-green-600' },
  { id: 'outstation',  label: 'Outstation',    icon: Map,       description: 'One-way and round trips',        href: '/services/outstation',  color: 'bg-purple-50 text-purple-600' },
  { id: 'delivery',    label: 'Delivery',      icon: Package,   description: 'Package and goods delivery',     href: '/services/delivery',    color: 'bg-orange-50 text-orange-600' },
  { id: 'goods',       label: 'Goods',         icon: Truck,     description: 'Large goods transportation',     href: '/services/delivery',    color: 'bg-yellow-50 text-yellow-600' },
  { id: 'hire_driver', label: 'Hire a Driver', icon: UserCheck, description: 'Book a driver for your own car', href: '/services/hire-driver', color: 'bg-pink-50 text-pink-600' },
]

export default function ServicesPage() {
  const [toggles, setToggles] = useState<Record<string, boolean>>({
    taxi: true, rental: true, outstation: true, delivery: true, goods: false, hire_driver: true,
  })
  const [toast, setToast] = useState<{ msg: string } | null>(null)

  useEffect(() => {
    fetch('/api/services')
      .then(r => r.json())
      .then(d => {
        const map: Record<string, boolean> = { taxi: true, rental: true, outstation: true, delivery: true, goods: false, hire_driver: true }
        ;(d.services || []).forEach((s: any) => { map[s.service] = s.isActive })
        setToggles(map)
      })
      .catch(() => {})
  }, [])

  const toggle = async (id: string) => {
    const next = { ...toggles, [id]: !toggles[id] }
    setToggles(next)
    setToast({ msg: `${id.charAt(0).toUpperCase() + id.slice(1)} service ${next[id] ? 'enabled' : 'disabled'}` })
    await fetch('/api/services', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ service: id, isActive: next[id] }),
    })
  }

  const activeCount = Object.values(toggles).filter(Boolean).length

  return (
    <div>
      <Header title="Services" />
      <div className="p-6 space-y-6">
        <PageHeader title="Services" subtitle="Enable or disable services and configure pricing" />

        <div className="bg-blue-50 border border-blue-200 rounded-xl px-5 py-3 flex items-center gap-2">
          <span className="text-blue-800 text-sm font-medium">{activeCount} of {servicesList.length} services are currently active</span>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-4">
          {servicesList.map(s => (
            <div key={s.id} className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
              <div className="flex items-start justify-between mb-3">
                <div className={`w-12 h-12 rounded-xl ${s.color} flex items-center justify-center`}>
                  <s.icon className="w-6 h-6" />
                </div>
                <button type="button" title={`Toggle ${s.label}`}
                  onClick={() => toggle(s.id)}
                  className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${toggles[s.id] ? 'bg-primary' : 'bg-gray-200'}`}>
                  <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow-sm transition-transform ${toggles[s.id] ? 'translate-x-6' : 'translate-x-1'}`} />
                </button>
              </div>
              <h3 className="font-bold text-gray-900 text-base">{s.label}</h3>
              <p className="text-sm text-gray-500 mt-1 mb-4">{s.description}</p>
              <Link href={s.href}
                className="flex items-center gap-1 text-sm text-blue-600 font-medium hover:text-blue-800">
                Configure Pricing <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
          ))}
        </div>
      </div>
      {toast && <Toast message={toast.msg} type="info" onClose={() => setToast(null)} />}
    </div>
  )
}

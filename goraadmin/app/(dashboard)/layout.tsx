import { Sidebar } from '@/components/sidebar'

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="h-screen overflow-hidden bg-gray-50">
      <Sidebar />
      <div className="lg:pl-64 h-full flex flex-col overflow-hidden">
        {children}
      </div>
    </div>
  )
}

'use client'
import { Header } from '@/components/header'
import { DocumentTypesManager } from '@/components/document-types-manager'

// The documents a driver uploads at registration (also under Settings →
// Driver App → Registration Documents).
export default function DocumentTypesPage() {
  return (
    <div>
      <Header title="Driver Documents" />
      <div className="p-6">
        <DocumentTypesManager />
      </div>
    </div>
  )
}

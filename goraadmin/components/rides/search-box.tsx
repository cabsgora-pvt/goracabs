'use client'
import { useEffect, useState } from 'react'
import { Search } from 'lucide-react'

// Search input that searches on the server: applies on Enter or when it loses
// focus (so a paged list is searched as a whole, not just the loaded page).
export function SearchBox({ value, onSearch, placeholder, className = '' }: { value: string; onSearch: (v: string) => void; placeholder?: string; className?: string }) {
  const [v, setV] = useState(value)
  useEffect(() => { setV(value) }, [value])
  const apply = () => { const t = v.trim(); if (t !== value) onSearch(t) }
  return (
    <form className={`relative flex-1 min-w-[200px] ${className}`} onSubmit={e => { e.preventDefault(); apply() }}>
      <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
      <input type="text" value={v} onChange={e => setV(e.target.value)} onBlur={apply} aria-label="Search"
        placeholder={(placeholder || 'Search') + ' — Enter to search'}
        className="w-full pl-9 pr-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
    </form>
  )
}

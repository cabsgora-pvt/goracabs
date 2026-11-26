'use client'
// Previous / Page x of y / Next, with the true total from the API (same look
// as the audit-log and review pages).
export function RidesPager({ page, limit, total, onPage, loading }: { page: number; limit: number; total: number; onPage: (p: number) => void; loading?: boolean }) {
  const pages = Math.max(1, Math.ceil((Number(total) || 0) / limit))
  const from = total === 0 ? 0 : (page - 1) * limit + 1
  const to = Math.min(total, page * limit)
  return (
    <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 border-t border-gray-100 text-sm text-gray-600">
      <span>{loading ? 'Loading…' : total === 0 ? 'No results' : `Showing ${from}–${to} of ${total.toLocaleString('en-IN')}`}</span>
      <div className="flex items-center gap-2">
        <button type="button" className="px-3 py-1.5 border rounded-lg disabled:opacity-40" disabled={page <= 1 || loading} onClick={() => onPage(page - 1)}>Previous</button>
        <span>Page {page} of {pages}</span>
        <button type="button" className="px-3 py-1.5 border rounded-lg disabled:opacity-40" disabled={page >= pages || loading} onClick={() => onPage(page + 1)}>Next</button>
      </div>
    </div>
  )
}

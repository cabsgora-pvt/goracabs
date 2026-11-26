'use client'

/** Previous / Next pager with the true total, in the audit-log page's style. */
export function Pager({ page, limit, total, onPage, noun = ['entry', 'entries'] }: {
  page: number; limit: number; total: number; onPage: (p: number) => void; noun?: [string, string]
}) {
  const pages = Math.max(1, Math.ceil(total / limit))
  return (
    <div className="flex items-center justify-between text-sm text-gray-600 px-1 py-2">
      <span>{total} {total === 1 ? noun[0] : noun[1]}</span>
      <div className="flex items-center gap-2">
        <button type="button" className="px-3 py-1.5 border rounded-lg bg-white disabled:opacity-40" disabled={page <= 1} onClick={() => onPage(page - 1)}>Previous</button>
        <span>Page {Math.min(page, pages)} of {pages}</span>
        <button type="button" className="px-3 py-1.5 border rounded-lg bg-white disabled:opacity-40" disabled={page >= pages} onClick={() => onPage(page + 1)}>Next</button>
      </div>
    </div>
  )
}

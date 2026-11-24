// Shared paging / search helpers for the admin list APIs.

export const MAX_LIST_LIMIT = 200

/** page >= 1, 1 <= limit <= MAX_LIST_LIMIT (default 50). NaN-safe. */
export function parsePaging(sp: URLSearchParams, defaultLimit = 50) {
  const page = Math.max(1, Math.floor(Number(sp.get('page')) || 1))
  const limit = Math.min(MAX_LIST_LIMIT, Math.max(1, Math.floor(Number(sp.get('limit')) || defaultLimit)))
  return { page, limit, skip: (page - 1) * limit }
}

/** Escape a user-typed string for literal use inside a RegExp / Mongo $regex,
 *  capped in length so a search box cannot submit a pathological pattern. */
export function escapeRegex(s: string, max = 100): string {
  return String(s || '').slice(0, max).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

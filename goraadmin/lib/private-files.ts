import path from 'path'
import { unlink } from 'fs/promises'

// ─────────────────────────────────────────────────────────────────────────────
// Where uploads live.
//   public  → public/uploads/<name>, served by Next at /uploads/<name> to anyone
//             (profile and vehicle photos, notification banners)
//   private → data/private-uploads/<name>, served only by GET /api/files/<name>
//             to the owner, admins, the owner's zone admin and — for delivery
//             proofs — the ride's rider/driver (KYC documents, face photos,
//             delivery proofs). Upload with ?private=1 (or form field private=1).
// In production data/ is a symlink outside the code dir, so private files
// survive redeploys. Documents uploaded before this change keep their public
// /uploads URLs until they are migrated (see report).
// ─────────────────────────────────────────────────────────────────────────────

export const PUBLIC_DIR = () => path.join(process.cwd(), 'public', 'uploads')
export const PRIVATE_DIR = () => path.join(process.cwd(), 'data', 'private-uploads')
export const PRIVATE_PREFIX = '/api/files/'

/** Names we generate: <ms>-<12 hex>.<ext>. Anything else is refused. */
export const FILE_NAME_RE = /^\d{10,16}-[a-f0-9]{12}\.(jpg|png|webp|gif|pdf)$/

/** Is this a URL of a file we stored (public or private)? */
export function isStoredFileUrl(u: unknown): boolean {
  return typeof u === 'string' && !!storedFilePath(u)
}

/** Absolute disk path of a stored-file URL, or null if it is not one of ours. */
export function storedFilePath(u: string): string | null {
  const s = String(u || '').trim()
  let m = s.match(/^(?:https?:\/\/[^/]+)?\/uploads\/([^/?#]+)$/)
  if (m && FILE_NAME_RE.test(m[1])) return path.join(PUBLIC_DIR(), m[1])
  m = s.match(/^(?:https?:\/\/[^/]+)?\/api\/files\/([^/?#]+)$/)
  if (m && FILE_NAME_RE.test(m[1])) return path.join(PRIVATE_DIR(), m[1])
  return null
}

/** Best-effort removal of stored files (account deletion). Never throws. */
export async function deleteStoredFiles(urls: unknown[]): Promise<number> {
  let n = 0
  for (const u of new Set(urls.filter(x => typeof x === 'string' && x) as string[])) {
    const p = storedFilePath(u)
    if (!p) continue
    try { await unlink(p); n++ } catch { /* already gone */ }
  }
  return n
}

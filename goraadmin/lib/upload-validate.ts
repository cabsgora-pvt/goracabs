// Validates an uploaded file by its content, never its name or Content-Type.
// Files land in public/uploads and are served from the admin origin, so an
// .html/.svg/.js upload would be stored XSS against the dashboard. Only the
// formats below are accepted, and the stored extension comes from the magic
// bytes we detected.
export const MAX_UPLOAD_BYTES = 8 * 1024 * 1024

export type DetectedType = { ext: 'jpg' | 'png' | 'webp' | 'gif' | 'pdf'; mime: string }

export function detectFileType(b: Buffer): DetectedType | null {
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return { ext: 'jpg', mime: 'image/jpeg' }
  if (b.length >= 8 && b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return { ext: 'png', mime: 'image/png' }
  if (b.length >= 12 && b.subarray(0, 4).toString('latin1') === 'RIFF' && b.subarray(8, 12).toString('latin1') === 'WEBP') return { ext: 'webp', mime: 'image/webp' }
  if (b.length >= 6 && (b.subarray(0, 6).toString('latin1') === 'GIF87a' || b.subarray(0, 6).toString('latin1') === 'GIF89a')) return { ext: 'gif', mime: 'image/gif' }
  if (b.length >= 5 && b.subarray(0, 5).toString('latin1') === '%PDF-') return { ext: 'pdf', mime: 'application/pdf' }
  return null
}

const ALLOWED_NAME_EXT = new Set(['jpg', 'jpeg', 'png', 'webp', 'gif', 'pdf'])

/** Returns an error message, or the detected type when the file is acceptable. */
export function validateUpload(name: string, size: number, buf: Buffer): { error: string } | { type: DetectedType } {
  if (!size || !buf.length) return { error: 'Empty file' }
  if (size > MAX_UPLOAD_BYTES || buf.length > MAX_UPLOAD_BYTES) return { error: 'File too large (max 8 MB)' }
  const nameExt = String(name || '').toLowerCase().split('.').pop() || ''
  // A name without an extension (some camera pickers) is fine; a wrong one is not.
  if (name && name.includes('.') && !ALLOWED_NAME_EXT.has(nameExt)) return { error: 'Only JPG, PNG, WEBP, GIF or PDF files are allowed' }
  const type = detectFileType(buf)
  if (!type) return { error: 'Only JPG, PNG, WEBP, GIF or PDF files are allowed' }
  return { type }
}

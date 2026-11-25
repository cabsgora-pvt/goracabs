// Removes GPS data from a JPEG's EXIF block, in place on a copy of the buffer,
// without a dependency (none of sharp/exifr is installed). Phone cameras write
// the exact place a document or selfie was shot; that must not reach storage.
// Everything else in EXIF (notably Orientation) is kept, so photos don't turn
// sideways. Only the GPS IFD pointer is cleared and the GPS IFD and its value
// bytes are zeroed. Any parse problem leaves the image untouched.

export function stripJpegGps(input: Buffer): { buf: Buffer; stripped: boolean } {
  const b = Buffer.from(input)
  try {
    if (b.length < 4 || b[0] !== 0xff || b[1] !== 0xd8) return { buf: input, stripped: false }
    let off = 2
    let stripped = false
    while (off + 4 <= b.length) {
      if (b[off] !== 0xff) break
      const marker = b[off + 1]
      if (marker === 0xd9 || marker === 0xda) break           // EOI / start of scan
      if (marker >= 0xd0 && marker <= 0xd7) { off += 2; continue }
      const len = b.readUInt16BE(off + 2)
      const segStart = off + 4, segEnd = off + 2 + len
      if (segEnd > b.length) break
      if (marker === 0xe1 && b.toString('latin1', segStart, segStart + 6) === 'Exif\0\0') {
        if (clearGps(b, segStart + 6, segEnd)) stripped = true
      }
      off = segEnd
    }
    return stripped ? { buf: b, stripped } : { buf: input, stripped: false }
  } catch {
    return { buf: input, stripped: false }
  }
}

const TYPE_SIZE: Record<number, number> = { 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8 }

function clearGps(b: Buffer, tiff: number, end: number): boolean {
  const order = b.toString('latin1', tiff, tiff + 2)
  const le = order === 'II'
  if (!le && order !== 'MM') return false
  const u16 = (o: number) => (le ? b.readUInt16LE(o) : b.readUInt16BE(o))
  const u32 = (o: number) => (le ? b.readUInt32LE(o) : b.readUInt32BE(o))
  const w32 = (o: number, v: number) => (le ? b.writeUInt32LE(v, o) : b.writeUInt32BE(v, o))
  const ifd0 = tiff + u32(tiff + 4)
  if (ifd0 + 2 > end) return false
  const n = u16(ifd0)
  for (let i = 0; i < n; i++) {
    const e = ifd0 + 2 + i * 12
    if (e + 12 > end) return false
    if (u16(e) !== 0x8825) continue                     // GPSInfo IFD pointer
    const gps = tiff + u32(e + 8)
    if (gps + 2 <= end) {
      const gn = u16(gps)
      for (let j = 0; j < gn; j++) {
        const ge = gps + 2 + j * 12
        if (ge + 12 > end) break
        const size = (TYPE_SIZE[u16(ge + 2)] || 1) * u32(ge + 4)
        if (size > 4) {
          const vo = tiff + u32(ge + 8)
          if (vo + size <= end) b.fill(0, vo, vo + size)
        }
      }
      const gEnd = Math.min(end, gps + 2 + gn * 12 + 4)
      b.fill(0, gps, gEnd)
    }
    // Drop the GPSInfo entry from IFD0: shift the later entries and the
    // next-IFD offset up by one slot, then decrement the count.
    const tailStart = e + 12, tailEnd = ifd0 + 2 + n * 12 + 4
    if (tailEnd > end) { w32(e + 8, 0); return true }
    b.copy(b, e, tailStart, tailEnd)
    b.fill(0, tailEnd - 12, tailEnd)
    if (le) b.writeUInt16LE(n - 1, ifd0); else b.writeUInt16BE(n - 1, ifd0)
    return true
  }
  return false
}

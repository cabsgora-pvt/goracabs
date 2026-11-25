export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import AdminAudit from '@/models/AdminAudit'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging, escapeRegex } from '@/lib/list-params'

// GET ?page&limit&action=&email=&q=&from=YYYY-MM-DD&to=YYYY-MM-DD&generic=0|1
// Admin audit log, newest first. `action` is a prefix (e.g. "driver."),
// `q` matches path / target / summary. generic=0 hides the plain
// 'api.<METHOD>' rows that no route enriched.
export async function GET(req: NextRequest) {
  const denied = await guardAdmin(req); if (denied) return denied
  try {
    await connectDB()
    const sp = req.nextUrl.searchParams
    const { page, limit, skip } = parsePaging(sp, 50)
    const q: any = {}
    const action = (sp.get('action') || '').trim()
    if (action) q.action = { $regex: '^' + escapeRegex(action, 60) }
    else if (sp.get('generic') === '0') q.action = { $not: /^api\./ }
    const email = (sp.get('email') || '').trim()
    if (email) q.email = { $regex: escapeRegex(email, 100), $options: 'i' }
    const text = (sp.get('q') || '').trim()
    if (text) {
      const re = { $regex: escapeRegex(text, 100), $options: 'i' }
      q.$or = [{ path: re }, { target: re }, { summary: re }]
    }
    const day = (s: string | null) => (s && /^\d{4}-\d{2}-\d{2}$/.test(s) ? new Date(s + 'T00:00:00+05:30') : null)
    const from = day(sp.get('from')), to = day(sp.get('to'))
    if (from || to) q.at = { ...(from ? { $gte: from } : {}), ...(to ? { $lt: new Date(to.getTime() + 86_400_000) } : {}) }
    const [rows, total, actions] = await Promise.all([
      AdminAudit.find(q).sort({ at: -1 }).skip(skip).limit(limit).lean(),
      AdminAudit.countDocuments(q),
      AdminAudit.distinct('action'),
    ])
    return NextResponse.json({ rows, total, page, limit, actions: (actions as string[]).sort() })
  } catch {
    return NextResponse.json({ error: 'Could not load the audit log' }, { status: 500 })
  }
}

export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import FAQ from '@/models/FAQ'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET /api/faqs?for=rider|driver → { faqs: [{ q, a, category }] }
// Public: the FAQs the admin writes in Support → FAQ, for the apps' help
// screens (the admin API is admin-only, so the apps never saw them and showed
// built-in samples instead — one of them about "driver bidding", which Gora
// does not have). Riders get rider + payment + general; drivers driver + general.
export async function GET(req: NextRequest) {
  try {
    const who = req.nextUrl.searchParams.get('for') === 'driver' ? 'driver' : 'rider'
    const cats = who === 'driver' ? ['driver', 'general'] : ['rider', 'payment', 'general']
    await connectDB()
    const rows: any[] = await FAQ.find({ isActive: true, category: { $in: cats } })
      .sort({ sortOrder: 1, createdAt: 1 }).limit(50).select('question answer category').lean()
    return withCors({
      faqs: rows
        .filter(f => (f.question || '').trim())
        .map(f => ({ q: String(f.question).trim(), a: String(f.answer || '').trim(), category: f.category || 'general' })),
    })
  } catch {
    return withCors({ faqs: [] })
  }
}

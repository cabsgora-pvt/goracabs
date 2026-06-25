import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import { withCors, corsOptions } from '@/lib/cors'
import AppConfig from '@/models/AppConfig'

export async function OPTIONS() { return corsOptions() }

// GET /api/app-config?app=user  → returns the config (creates a default doc if none)
export async function GET(req: NextRequest) {
  try {
    await connectDB()
    const app = req.nextUrl.searchParams.get('app') || 'user'
    let cfg = await AppConfig.findOne({ app }).lean()
    if (!cfg) {
      cfg = (await AppConfig.create({ app })).toObject()
    }
    return withCors({ config: cfg })
  } catch (e: any) {
    return withCors({ error: e.message }, 500)
  }
}

// POST /api/app-config  body: { app, ...sections }  → upsert (admin)
export async function POST(req: NextRequest) {
  try {
    await connectDB()
    const body = await req.json()
    const app = body.app || 'user'
    delete body.app
    const cfg = await AppConfig.findOneAndUpdate(
      { app },
      { $set: { ...body, app } },
      { new: true, upsert: true, setDefaultsOnInsert: true },
    ).lean()
    return withCors({ config: cfg })
  } catch (e: any) {
    return withCors({ error: e.message }, 400)
  }
}

import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import { requireRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// Completes a rider profile after OTP sign-in. Never touches `status`: a
// blocked or deleted rider must not be able to reactivate by re-registering.
const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,}$/

function str(v: unknown, max: number): string | undefined | null {
  if (v === undefined || v === null) return undefined
  if (typeof v !== 'string') return null
  const t = v.trim()
  return t.length > max ? null : t
}

export async function POST(req: NextRequest) {
  try {
    const payload = requireRider(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const b = await req.json().catch(() => null)
    if (!b || typeof b !== 'object') return withCors({ error: 'Invalid request' }, 400)

    const name = str(b.name, 80)
    const city = str(b.city, 80)
    const email = str(b.email, 254)
    const idNumber = str(b.idNumber, 40)
    const profilePicUrl = str(b.profilePicUrl, 500)
    if (name === null || !name) return withCors({ error: 'Name is required (max 80 characters)' }, 400)
    if (city === null) return withCors({ error: 'Invalid city' }, 400)
    if (email === null || (email && !EMAIL_RE.test(email))) return withCors({ error: 'Invalid email' }, 400)
    if (idNumber === null) return withCors({ error: 'Invalid ID number' }, 400)
    if (profilePicUrl === null || (profilePicUrl && !/^(\/uploads\/[\w.-]+|https?:\/\/\S+)$/.test(profilePicUrl))) {
      return withCors({ error: 'Invalid profile picture' }, 400)
    }

    await connectDB()
    const existing: any = await User.findById(payload.id).select('status').lean()
    if (!existing) return withCors({ error: 'User not found' }, 404)
    if (existing.status !== 'active') return withCors({ error: 'This account is not active. Contact support.' }, 403)

    const set: Record<string, string> = { name }
    if (city !== undefined) set.city = city
    if (email !== undefined) set.email = email.toLowerCase()
    if (idNumber !== undefined) set.idNumber = idNumber
    if (profilePicUrl !== undefined) set.profilePicUrl = profilePicUrl

    const user = await User.findOneAndUpdate({ _id: payload.id, status: 'active' }, { $set: set }, { new: true }).lean()
    if (!user) return withCors({ error: 'User not found' }, 404)

    return withCors({ success: true, user })
  } catch {
    return withCors({ error: 'Registration failed' }, 500)
  }
}

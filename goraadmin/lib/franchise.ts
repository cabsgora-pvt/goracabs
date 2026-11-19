import { connectDB } from '@/lib/mongodb'
import Settings from '@/models/Settings'

// Franchise mode: the super admin's switch for the whole zone admin system.
// Off (the default) runs the app as it was before franchises: no zone panel
// sign-in, zone admin promo codes not valid, no zone helplines. Their data is
// kept and comes back as it was when it is switched on again.

let cache: { value: boolean; at: number } | null = null
const TTL_MS = 10_000

export async function isFranchiseMode(): Promise<boolean> {
  if (cache && Date.now() - cache.at < TTL_MS) return cache.value
  await connectDB()
  const s: any = await Settings.findOne({ key: 'global' }).select('franchise').lean()
  const value = s?.franchise?.enabled === true
  cache = { value, at: Date.now() }
  return value
}

export async function setFranchiseMode(enabled: boolean, by?: string) {
  await connectDB()
  await Settings.updateOne(
    { key: 'global' },
    { $set: { 'franchise.enabled': enabled, 'franchise.changedAt': new Date(), 'franchise.changedBy': by || '' } },
    { upsert: true },
  )
  cache = { value: enabled, at: Date.now() }
}

export const FRANCHISE_OFF_MESSAGE = 'The zone admin panel is not available right now. Please contact Gora.'

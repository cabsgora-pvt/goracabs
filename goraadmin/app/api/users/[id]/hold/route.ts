import { NextRequest } from 'next/server'
import User from '@/models/User'
import { setHold } from '@/lib/admin-account'

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  return setHold(req, User, params.id, false)
}

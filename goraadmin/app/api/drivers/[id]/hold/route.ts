import { NextRequest } from 'next/server'
import Driver from '@/models/Driver'
import { setHold } from '@/lib/admin-account'

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  return setHold(req, Driver, params.id, true)
}

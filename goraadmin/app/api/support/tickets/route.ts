import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SupportTicket from '@/models/SupportTicket'
import User from '@/models/User'
import Driver from '@/models/Driver'
import Ride from '@/models/Ride'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging, escapeRegex } from '@/lib/list-params'

const TICKET_STATUSES = ['open', 'in_progress', 'resolved', 'closed']

// GET ?status=open|in_progress|resolved|closed|unresolved|all &priority=low|medium|high
//     &role=user|driver &q=<subject / name / phone> &sort=newest|oldest|oldest_open &page&limit
// oldest_open: open, then in progress, oldest first in each (the queue), then
// the rest newest first. Each ticket carries its linked rider / driver / ride
// (name, phone, ride number) for links. `counts` is per status over the whole
// collection (stat cards), not this page.
export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const sp = req.nextUrl.searchParams
    const { page, limit, skip } = parsePaging(sp)
    const status = sp.get('status') || ''
    const priority = sp.get('priority') || ''
    const role = sp.get('role') || ''
    const q = escapeRegex((sp.get('q') || '').trim())
    const sort = sp.get('sort') || 'newest'

    const query: any = {}
    if (status === 'unresolved') query.status = { $in: ['open', 'in_progress'] }
    else if (TICKET_STATUSES.includes(status)) query.status = status
    if (['low', 'medium', 'high'].includes(priority)) query.priority = priority
    if (role === 'user' || role === 'driver') query.role = role
    if (q) query.$or = [{ subject: { $regex: q, $options: 'i' } }, { userName: { $regex: q, $options: 'i' } }, { driverPhone: { $regex: q, $options: 'i' } }]

    let tickets: any[]
    if (sort === 'oldest_open') {
      tickets = await SupportTicket.aggregate([
        { $match: query },
        { $addFields: { _rank: { $switch: { branches: [
          { case: { $eq: ['$status', 'open'] }, then: 0 },
          { case: { $eq: ['$status', 'in_progress'] }, then: 1 },
        ], default: 2 } } } },
        // Within the queue oldest first; resolved / closed newest first.
        { $addFields: { _t: { $cond: [{ $lt: ['$_rank', 2] }, { $toLong: '$createdAt' }, { $multiply: [-1, { $toLong: '$createdAt' }] }] } } },
        { $sort: { _rank: 1, _t: 1, _id: 1 } },
        { $skip: skip }, { $limit: limit },
        { $project: { _rank: 0, _t: 0 } },
      ])
    } else {
      tickets = await SupportTicket.find(query).sort({ createdAt: sort === 'oldest' ? 1 : -1, _id: 1 }).skip(skip).limit(limit).lean()
    }
    const [total, byStatus] = await Promise.all([
      SupportTicket.countDocuments(query),
      SupportTicket.aggregate([{ $group: { _id: '$status', n: { $sum: 1 } } }]),
    ])
    const counts: Record<string, number> = { open: 0, in_progress: 0, resolved: 0, closed: 0 }
    for (const b of byStatus) if (b._id) counts[b._id] = b.n

    // Linked records, one query each (no N+1).
    const ids = (k: string) => Array.from(new Set(tickets.map(t => t[k] && String(t[k])).filter(Boolean)))
    const [users, drivers, rides] = await Promise.all([
      ids('userId').length ? User.find({ _id: { $in: ids('userId') } }).select('name phone').lean() : [],
      ids('driverId').length ? Driver.find({ _id: { $in: ids('driverId') } }).select('name phone').lean() : [],
      ids('rideId').length ? Ride.find({ _id: { $in: ids('rideId') } }).select('service status createdAt').lean() : [],
    ]) as any[][]
    const map = (rows: any[]) => new Map(rows.map(r => [String(r._id), r]))
    const um = map(users), dm = map(drivers), rm = map(rides)
    const out = tickets.map(t => ({
      ...t,
      user: t.userId ? um.get(String(t.userId)) || null : null,
      driver: t.driverId ? dm.get(String(t.driverId)) || null : null,
      ride: t.rideId ? rm.get(String(t.rideId)) || null : null,
    }))
    return NextResponse.json({ tickets: out, total, page, limit, counts })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const body = await req.json()
    const ticket = await SupportTicket.create(body)
    return NextResponse.json(ticket, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import PushNotification from '@/models/PushNotification'

export async function GET() {
  try {
    await connectDB()
    const notifications = await PushNotification.find().sort({ sentAt: -1 }).limit(100).lean()
    return NextResponse.json({ notifications })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    await connectDB()
    const body = await req.json()
    const { title, message, target, targetUserId } = body
    if (!title || !message) {
      return NextResponse.json({ error: 'Title and message are required' }, { status: 400 })
    }

    const targetLabels: Record<string, string> = {
      all: 'All Users',
      riders: 'All Riders',
      drivers: 'All Drivers',
      specific: 'Specific User',
    }

    const notification = await PushNotification.create({
      title,
      message,
      target: target || 'all',
      targetUserId: targetUserId || '',
      sentAt: new Date(),
      deliveredCount: Math.floor(Math.random() * 500) + 100,
    })

    return NextResponse.json({
      success: true,
      notification: notification.toObject(),
      targetLabel: targetLabels[target] || target,
    }, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

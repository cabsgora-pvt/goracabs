import AccountRequest from '@/models/AccountRequest'

export const DELETE_REASONS = [
  'I no longer need the app',
  'I have another account',
  'Privacy concerns',
  'Too expensive',
  'Bad experience',
  'Other',
]

/** Open (pending) requests of one person, newest first. */
export async function openRequests(userType: 'rider' | 'driver', userId: string) {
  return AccountRequest.find({ userType, userId, status: 'pending' }).sort({ createdAt: -1 }).lean()
}

export function publicRequest(r: any) {
  return {
    id: String(r._id), kind: r.kind, status: r.status, reason: r.reason || '', note: r.note || '',
    toZoneName: r.toZoneName || '', adminNote: r.adminNote || '', createdAt: r.createdAt, handledAt: r.handledAt || null,
  }
}

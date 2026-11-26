// Rider-facing support ticket shape (app/api/user/support/tickets/**).
export const TICKET_LIMITS = { SUBJECT: 140, MESSAGE: 2000, PER_10_MIN: 5 }
export const TICKET_CATEGORIES = new Set(['ride', 'payment', 'driver', 'app', 'safety', 'account', 'general'])

export function ticketView(t: any) {
  return {
    id: String(t._id),
    subject: t.subject || '',
    category: t.category || 'general',
    status: t.status || 'open',
    rideId: t.rideId ? String(t.rideId) : null,
    createdAt: t.createdAt,
    updatedAt: t.updatedAt,
    messages: (t.messages || []).map((m: any) => ({ sender: m.sender, message: m.message, sentAt: m.sentAt })),
  }
}

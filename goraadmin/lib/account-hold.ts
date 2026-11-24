// Account hold helpers shared by the apps' gates and the admin panel.

export type HoldKind = 'face' | 'wallet' | 'manual' | 'other'

export const HOLD_KIND_LABEL: Record<HoldKind, string> = {
  face: 'Wrong face scan',
  wallet: 'Wallet mis-transaction',
  manual: 'Held by admin',
  other: 'Other',
}

/** Is this rider/driver on hold, and why. A driver who failed a mid-ride face
 *  check (faceVerificationRequired) is on hold too, until they re-verify or an
 *  admin releases them. */
export function holdOf(doc: any): { held: boolean; kind?: HoldKind; reason?: string } {
  if (doc?.accountHold?.active) {
    const kind = (doc.accountHold.kind || 'manual') as HoldKind
    return { held: true, kind, reason: doc.accountHold.reason || HOLD_KIND_LABEL[kind] }
  }
  if (doc?.faceVerificationRequired) {
    return { held: true, kind: 'face', reason: 'Face scan did not match. Please re-verify your face or contact support.' }
  }
  return { held: false }
}

export function holdMessage(h: { kind?: HoldKind; reason?: string }): string {
  return `Your account is on hold: ${h.reason || HOLD_KIND_LABEL[h.kind || 'manual']}. Please contact support.`
}

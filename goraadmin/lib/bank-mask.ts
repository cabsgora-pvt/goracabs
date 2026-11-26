// Bank details for admin lists: never the full account number.

/** Masked bank block for lists: last 4 of the account, never the number. */
export function maskBank(b: any) {
  if (!b || !b.accountNumber) return null
  return {
    accountHolderName: b.accountHolderName || '',
    bankName: b.bankName || '',
    branch: b.branch || '',
    ifscCode: b.ifscCode || '',
    accountType: b.accountType || 'savings',
    accountLast4: String(b.accountNumber).replace(/\s/g, '').slice(-4),
  }
}


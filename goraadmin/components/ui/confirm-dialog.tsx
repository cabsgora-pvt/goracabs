'use client'
import { useState } from 'react'
import { AlertTriangle } from 'lucide-react'
import { Modal } from './modal'

/**
 * Confirmation step before a destructive or money action. Render it when
 * there is something to confirm; onConfirm may be async — the button shows
 * "Working…" until it settles and the dialog stays open if it throws.
 */
export function ConfirmDialog({ title, message, confirmLabel = 'Confirm', tone = 'danger', onConfirm, onClose, children }: {
  title: string
  message: React.ReactNode
  confirmLabel?: string
  tone?: 'danger' | 'primary'
  onConfirm: () => void | Promise<void>
  onClose: () => void
  children?: React.ReactNode
}) {
  const [busy, setBusy] = useState(false)
  const go = async () => {
    if (busy) return
    setBusy(true)
    try { await onConfirm() } finally { setBusy(false) }
  }
  return (
    <Modal title={title} onClose={() => { if (!busy) onClose() }} size="sm">
      <div className="space-y-4">
        <div className="flex items-start gap-3">
          <div className={`w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0 ${tone === 'danger' ? 'bg-red-50 text-red-600' : 'bg-primary/10 text-primary'}`}>
            <AlertTriangle className="w-5 h-5" />
          </div>
          <div className="text-sm text-gray-700 pt-1">{message}</div>
        </div>
        {children}
        <div className="flex gap-3">
          <button type="button" onClick={onClose} disabled={busy}
            className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50 disabled:opacity-50">Cancel</button>
          <button type="button" onClick={go} disabled={busy} data-confirm="yes"
            className={`flex-1 text-white rounded-lg py-2 text-sm font-medium disabled:opacity-50 ${tone === 'danger' ? 'bg-red-600 hover:bg-red-700' : 'bg-primary hover:opacity-90'}`}>
            {busy ? 'Working…' : confirmLabel}
          </button>
        </div>
      </div>
    </Modal>
  )
}

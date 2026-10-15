// Cosine similarity between two face embeddings (MobileFaceNet-style vectors
// from the driver app's on-device model). The match decision always happens
// here, server-side — the device's own opinion is never trusted, since the
// whole point of this check is to catch a phone that isn't being honest.

// A starting threshold, not a calibrated one — there is no production dataset
// to tune this against yet. MobileFaceNet embeddings for the same person
// typically land well above 0.6 cosine similarity; different people well
// below 0.4. If false mismatches turn out to be common in practice, raise
// VERIFICATION_WINDOW_SEC/relax this first before assuming the model is wrong.
export const FACE_MATCH_THRESHOLD = 0.55

// How long a driver has to respond to a mid-ride check before it counts as
// a no-response (treated the same as a mismatch).
export const VERIFICATION_WINDOW_SEC = 60

export function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length || a.length === 0) return -1
  let dot = 0, normA = 0, normB = 0
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i]
    normA += a[i] * a[i]
    normB += b[i] * b[i]
  }
  if (normA === 0 || normB === 0) return -1
  return dot / (Math.sqrt(normA) * Math.sqrt(normB))
}

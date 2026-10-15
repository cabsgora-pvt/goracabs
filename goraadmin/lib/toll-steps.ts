// ─────────────────────────────────────────────────────────────────────────────
// Does a Google Directions step run on a toll road?
//
// The Directions API has no toll field and no toll price. What it does do is
// add a note beneath the instruction of every step on a toll road:
//
//   "Merge onto <b>NH48</b><div style=\"font-size:0.9em\">Toll road</div>"
//
// ("Partial toll road" when only part of the step is tolled). So the flag is
// read from those <div> NOTES only — never the main instruction, which in India
// is full of place names like "Dahisar Toll Naka" that are not toll roads.
//
// The driver app uses the flag to ask, once a toll road is behind it, whether a
// toll was paid. It is an aid, never a charge: the amount is always what the
// driver enters.
// ─────────────────────────────────────────────────────────────────────────────

// English, and Hindi for requests made with language=hi. The Hindi wording is
// not verified against live responses; the driver can always add a toll by hand.
const TOLL_NOTE = /\btoll road\b|टोल\s*(?:रोड|सड़क|मार्ग)/i

/** True when a step's raw html_instructions carry a toll-road note. */
export function isTollStep(htmlInstructions: string | undefined | null): boolean {
  const html = htmlInstructions || ''
  const notes = html.match(/<div[^>]*>[\s\S]*?<\/div>/gi) || []
  return notes.some(n => TOLL_NOTE.test(n.replace(/<[^>]+>/g, ' ')))
}

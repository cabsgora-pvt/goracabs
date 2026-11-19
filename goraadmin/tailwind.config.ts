import type { Config } from 'tailwindcss'

// The admin wears the look of the client's previous panel (Velzon theme):
// indigo #405189 brand, teal success, coral danger, amber warning. Remapping
// the palettes here restyles every page's existing blue/green/red/yellow
// classes without touching the pages themselves.

function mix(hex: string, to: string, amount: number): string {
  const p = (h: string) => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16))
  const a = p(hex), b = p(to)
  return '#' + a.map((v, i) => Math.round(v + (b[i] - v) * amount).toString(16).padStart(2, '0')).join('')
}

/** A 50–900 scale with [base] at shade [at]. */
function scale(base: string, at: 500 | 600) {
  const W = '#ffffff', K = '#000000'
  const lighter = at === 600
    ? { 50: 0.93, 100: 0.86, 200: 0.72, 300: 0.52, 400: 0.3, 500: 0.12 }
    : { 50: 0.93, 100: 0.86, 200: 0.72, 300: 0.52, 400: 0.26 }
  const darker = at === 600
    ? { 700: 0.15, 800: 0.3, 900: 0.45 }
    : { 600: 0.1, 700: 0.22, 800: 0.35, 900: 0.5 }
  const out: Record<string, string> = { [at]: base }
  for (const [k, v] of Object.entries(lighter)) out[k] = mix(base, W, v)
  for (const [k, v] of Object.entries(darker)) out[k] = mix(base, K, v)
  return out
}

const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        primary: { DEFAULT: '#405189', dark: '#364574', light: '#5a6aa0' },
        blue: scale('#405189', 600),
        indigo: scale('#405189', 600),
        green: scale('#0ab39c', 600),
        emerald: scale('#0ab39c', 600),
        red: scale('#f06548', 500),
        yellow: scale('#f7b84b', 500),
        amber: scale('#f7b84b', 500),
        sky: scale('#299cdb', 500),
        cyan: scale('#299cdb', 500),
      },
      fontFamily: {
        sans: ['Poppins', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
export default config

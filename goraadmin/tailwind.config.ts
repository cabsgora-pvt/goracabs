import type { Config } from 'tailwindcss'
const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        primary: { DEFAULT: '#1565C0', dark: '#0D47A1', light: '#1E88E5' }
      }
    }
  },
  plugins: []
}
export default config

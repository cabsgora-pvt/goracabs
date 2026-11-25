/** @type {import('next').NextConfig} */
const isProd = process.env.NODE_ENV === 'production'

// Admin pages: own origin + Google Maps (JS API, tiles, fonts). Next 14 inlines
// bootstrap scripts, so script-src needs 'unsafe-inline' (no nonce plumbing);
// dev mode also needs 'unsafe-eval' for React refresh.
const csp = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${isProd ? '' : " 'unsafe-eval'"} https://maps.googleapis.com https://maps.gstatic.com`,
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  "img-src 'self' data: blob: https:",
  "font-src 'self' data: https://fonts.gstatic.com",
  "connect-src 'self' https://maps.googleapis.com https://*.googleapis.com https://*.gstatic.com",
  "worker-src 'self' blob:",
  "frame-src 'self' https://www.google.com https://maps.google.com",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
].join('; ')

const common = [
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=(self)' },
  // Browsers ignore HSTS over plain http (local dev), so it is always sent.
  { key: 'Strict-Transport-Security', value: 'max-age=31536000; includeSubDomains' },
]

const nextConfig = {
  poweredByHeader: false,
  async headers() {
    return [
      // Everything except the public tracking page: no framing at all.
      {
        source: '/((?!track/).*)',
        headers: [...common, { key: 'X-Frame-Options', value: 'DENY' }, { key: 'Content-Security-Policy', value: csp }],
      },
      // /track/<id> is shared with riders' contacts and may be embedded by our
      // own site only.
      {
        source: '/track/:path*',
        headers: [...common, { key: 'X-Frame-Options', value: 'SAMEORIGIN' },
          { key: 'Content-Security-Policy', value: csp.replace("frame-ancestors 'none'", "frame-ancestors 'self'") }],
      },
      {
        source: '/uploads/:path*',
        headers: [
          { key: 'Access-Control-Allow-Origin', value: '*' },
          { key: 'Access-Control-Allow-Methods', value: 'GET' },
        ],
      },
    ]
  },
}
module.exports = nextConfig

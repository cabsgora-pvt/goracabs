// Shared safety gate for destructive scripts (seed.js, clear-data.js).
//
// Refuses to touch a database unless EITHER
//   • its name looks like a throwaway one (contains "dev" or "test"), OR
//   • the caller passed --i-know-this-wipes AND typed the database name back
//     at an interactive prompt.
// Both scripts delete collections wholesale; a stray MONGODB_URI pointing at
// production must never be enough on its own.
const readline = require('readline')

function dbNameFromUri(uri) {
  try {
    const noProto = String(uri).replace(/^mongodb(\+srv)?:\/\//, '')
    const afterHost = noProto.slice(noProto.indexOf('/') + 1)
    if (noProto.indexOf('/') === -1) return ''
    return decodeURIComponent(afterHost.split('?')[0] || '')
  } catch { return '' }
}

function hostFromUri(uri) {
  const noProto = String(uri).replace(/^mongodb(\+srv)?:\/\//, '')
  const hostPart = noProto.split('/')[0]
  return hostPart.includes('@') ? hostPart.split('@').pop() : hostPart
}

function ask(q) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout })
  return new Promise(res => rl.question(q, a => { rl.close(); res(a) }))
}

/** Resolves when allowed; exits the process otherwise. Never prints credentials. */
async function assertSafeToWipe(uri, what) {
  const name = dbNameFromUri(uri)
  const host = hostFromUri(uri)
  if (!name) {
    console.error('Refusing: MONGODB_URI has no database name.')
    process.exit(1)
  }
  if (/dev|test/i.test(name)) return
  if (!process.argv.includes('--i-know-this-wipes')) {
    console.error(`Refusing to ${what} database "${name}" on ${host}.`)
    console.error('Its name does not look like a dev/test database. If you really mean it, re-run with')
    console.error('--i-know-this-wipes and type the database name when asked.')
    process.exit(1)
  }
  if (!process.stdin.isTTY) {
    console.error('Refusing: --i-know-this-wipes needs an interactive terminal to confirm.')
    process.exit(1)
  }
  const typed = (await ask(`This will ${what} database "${name}" on ${host}. Type the database name to continue: `)).trim()
  if (typed !== name) {
    console.error('Name did not match — nothing was changed.')
    process.exit(1)
  }
}

module.exports = { assertSafeToWipe, dbNameFromUri }

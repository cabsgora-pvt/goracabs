import fs from 'fs'
import path from 'path'

const settingsPath = path.join(process.cwd(), 'data', 'settings.json')

export function getSettings() {
  const raw = fs.readFileSync(settingsPath, 'utf-8')
  return JSON.parse(raw)
}

export function saveSettings(data: any) {
  fs.writeFileSync(settingsPath, JSON.stringify(data, null, 2))
}

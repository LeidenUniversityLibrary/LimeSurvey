const fs = require('node:fs')
const path = require('node:path')

const editorDirectory = path.resolve(__dirname, '..')
const html = fs.readFileSync(path.join(editorDirectory, 'index.html'), 'utf8')
const assetPaths = [...html.matchAll(/(?:src|href)="(build\/[^"?#]+)"/g)].map(
  (match) => match[1]
)
const missingAssets = assetPaths.filter(
  (assetPath) => !fs.existsSync(path.join(editorDirectory, assetPath))
)

if (missingAssets.length > 0) {
  console.error(`Editor index.html references missing assets:\n${missingAssets.join('\n')}`)
  process.exitCode = 1
} else {
  console.log(`Verified ${assetPaths.length} editor assets.`)
}

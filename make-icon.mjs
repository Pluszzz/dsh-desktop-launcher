// DSH desktop icon builder.
// 1) Reads the whale path extracted from apps/web/public/favicon.svg,
//    computes its bounding box by sampling cubic segments,
//    and emits a 512x512 SVG: DeepSeek-blue rounded square + white whale.
// 2) Packs pre-rendered PNG sizes (16..256) into a multi-entry .ico.
// Render step (Edge headless) runs outside this script.

import { readFileSync, writeFileSync, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const WHALE = readFileSync(join(here, 'whale-path.txt'), 'utf8').trim()
const BLUE = '#4D6BFE'
const SIZE = 512
const RADIUS = 112
const PADDING = 0.09 // fraction of canvas kept free around the whale

function parsePath(d) {
  // Support the subset this path actually uses: M, C, Z (absolute).
  const tokens = d.match(/[A-Za-z]|-?\d*\.?\d+(?:e[+-]?\d+)?/g)
  const segments = []
  let i = 0
  let current = null
  while (i < tokens.length) {
    const cmd = tokens[i++]
    if (cmd === 'M') {
      current = { x: +tokens[i++], y: +tokens[i++] }
      segments.push({ kind: 'M', x: current.x, y: current.y })
    } else if (cmd === 'C') {
      const seg = {
        kind: 'C',
        x1: +tokens[i++], y1: +tokens[i++],
        x2: +tokens[i++], y2: +tokens[i++],
        x: +tokens[i++], y: +tokens[i++],
      }
      segments.push(seg)
      current = { x: seg.x, y: seg.y }
    } else if (cmd === 'Z') {
      segments.push({ kind: 'Z' })
    } else {
      throw new Error(`unsupported path command: ${cmd}`)
    }
  }
  return segments
}

function bboxOf(segments) {
  const S = 64 // samples per cubic
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  let cx = 0, cy = 0
  for (const seg of segments) {
    if (seg.kind === 'M') {
      cx = seg.x; cy = seg.y
      minX = Math.min(minX, cx); minY = Math.min(minY, cy)
      maxX = Math.max(maxX, cx); maxY = Math.max(maxY, cy)
    } else if (seg.kind === 'C') {
      for (let s = 0; s <= S; s++) {
        const t = s / S
        const u = 1 - t
        const x = u * u * u * cx + 3 * u * u * t * seg.x1 + 3 * u * t * t * seg.x2 + t * t * t * seg.x
        const y = u * u * u * cy + 3 * u * u * t * seg.y1 + 3 * u * t * t * seg.y2 + t * t * t * seg.y
        if (x < minX) minX = x
        if (y < minY) minY = y
        if (x > maxX) maxX = x
        if (y > maxY) maxY = y
      }
      cx = seg.x; cy = seg.y
    }
  }
  return { minX, minY, maxX, maxY }
}

function buildSvg(whalePath) {
  const segments = parsePath(whalePath)
  const { minX, minY, maxX, maxY } = bboxOf(segments)
  const w = maxX - minX
  const h = maxY - minY
  const scale = (SIZE * (1 - 2 * PADDING)) / Math.max(w, h)
  const tx = (SIZE - w * scale) / 2 - minX * scale
  const ty = (SIZE - h * scale) / 2 - minY * scale
  return {
    svg: `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">
  <rect width="${SIZE}" height="${SIZE}" rx="${RADIUS}" fill="${BLUE}"/>
  <g transform="translate(${tx.toFixed(3)} ${ty.toFixed(3)}) scale(${scale.toFixed(3)})">
    <path fill="#FFFFFF" d="${whalePath}"/>
  </g>
</svg>
`,
    info: { bbox: { minX, minY, maxX, maxY }, scale, tx, ty },
  }
}

function packIco(pngs) {
  // pngs: array of { size, data } sorted ascending. Single 256 entry is enough for
  // Explorer, but multiple sizes give crisp small glyphs on the taskbar.
  const count = pngs.length
  const header = Buffer.alloc(6)
  header.writeUInt16LE(0, 0) // reserved
  header.writeUInt16LE(1, 2) // type: icon
  header.writeUInt16LE(count, 4)
  let offset = 6 + 16 * count
  const chunks = [header]
  const entries = []
  for (const { size, data } of pngs) {
    const entry = Buffer.alloc(16)
    entry[0] = size >= 256 ? 0 : size
    entry[1] = size >= 256 ? 0 : size
    entry[2] = 0 // palette
    entry[3] = 0
    entry.writeUInt16LE(1, 4) // planes
    entry.writeUInt16LE(32, 6) // bpp
    entry.writeUInt32LE(data.length, 8)
    entry.writeUInt32LE(offset, 12)
    offset += data.length
    entries.push(entry)
  }
  chunks.push(...entries, ...pngs.map((p) => p.data))
  return Buffer.concat(chunks)
}

if (process.argv[2] === '--pack') {
  const sizes = [16, 32, 48, 64, 128, 256]
  const pngs = sizes
    .map((size) => {
      const file = join(here, `dsh-web-${size}.png`)
      if (!statSync(file, { throwIfNoEntry: false })) return null
      return { size, data: readFileSync(file) }
    })
    .filter(Boolean)
  if (pngs.length === 0) throw new Error('no PNG sizes found; render them first')
  writeFileSync(join(here, 'dsh-web.ico'), packIco(pngs))
  console.log(`packed dsh-web.ico with ${pngs.length} sizes: ${pngs.map((p) => p.size).join(', ')}`)
} else {
  const { svg, info } = buildSvg(WHALE)
  writeFileSync(join(here, 'dsh-web.svg'), svg)
  console.log(`whale bbox: ${JSON.stringify(info.bbox)}`)
  console.log(`scale=${info.scale.toFixed(3)} translate=(${info.tx.toFixed(1)}, ${info.ty.toFixed(1)})`)
  console.log('wrote dsh-web.svg')
}

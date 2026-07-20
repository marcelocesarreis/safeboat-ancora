/* Gera test/golden.json a partir do núcleo JS já testado, para o teste de
 * paridade Dart (flutter test) confirmar que o port não introduziu bug.
 *
 *   node gen-golden.cjs
 *
 * Estratégia: entradas DETERMINÍSTICAS (sem depender de igualdade bit-a-bit de
 * funções transcendentais entre V8 e Dart VM). O RNG é aritmética inteira (exato).
 * O trace do núcleo roda sobre fixes EMBUTIDOS no JSON, então os dois lados
 * processam exatamente a mesma entrada.
 */
const fs = require('fs')
const path = require('path')
const SBAnchor = require('../core/anchor-core.js')
const SBSim = require('../core/sim-device.js')
const { AnchorWatch } = SBAnchor

const out = {}

// ---- 1. RNG mulberry32 (paridade inteira exata) ----
{
  const rnd = SBSim.mulberry32(7)
  out.rng = { seed: 7, values: Array.from({ length: 12 }, () => rnd()) }
}

// ---- 2. gauss (tolerância pequena; usa sqrt/log/cos) ----
{
  const rnd = SBSim.mulberry32(42)
  out.gauss = { seed: 42, values: Array.from({ length: 8 }, () => SBSim.gauss(rnd)) }
}

// ---- 3. swingRadius / scopeRatio (geometria pura) ----
out.swing = [
  { rodeLength: 40, depth: 6, bowRoller: 1.2, boatLength: 8, gpsMargin: 5 },
  { rodeLength: 30, depth: 8, bowRoller: 1.0, boatLength: 10, gpsMargin: 4 },
  { rodeLength: 60, depth: 4, bowRoller: 1.2, boatLength: 12, gpsMargin: 6 },
].map((c) => ({
  cfg: c,
  radius: SBAnchor.swingRadius(c),
  scope: SBAnchor.scopeRatio(c),
}))

// ---- 4. fitCircle sobre um arco conhecido (sem RNG) ----
{
  const pts = []
  for (let a = -60; a <= 60; a += 5) {
    const r = 45, rad = (a * Math.PI) / 180
    pts.push({ x: 12 + r * Math.sin(rad), y: -7 + r * Math.cos(rad) })
  }
  const fit = SBAnchor.fitCircle(pts)
  out.fitCircle = { pts, fit: { x: fit.x, y: fit.y, r: fit.r, rms: fit.rms, span: fit.span } }
}

// ---- 5. Trace do núcleo sobre fixes DETERMINÍSTICOS ----
// Barco num arco perfeito em torno da âncora + garrada linear a partir de t=20min.
// Gera os fixes aqui e EMBUTE no JSON; o Dart replaya exatamente estes.
{
  const origin = { lat: -27.5954, lon: -48.548 }
  const m = { lat: 111132.92 - 559.82 * Math.cos(2 * origin.lat * Math.PI / 180), lon: 111412.84 * Math.cos(origin.lat * Math.PI / 180) }
  const t0 = 1_700_000_000_000
  const anchorX = 0, anchorY = 0
  const swingR = 30 // barco a 30 m da âncora
  const fixes = []
  // deriva: a partir de 20 min, âncora anda 0.9 m/min para leste (radial constante)
  for (let s = 0; s < 60 * 60; s++) {
    const min = s / 60
    const dragX = min > 20 ? (min - 20) * 0.9 : 0
    const ax = anchorX + dragX, ay = anchorY
    // guinada senoidal determinística ±25°, período 100 s
    const yaw = 25 * Math.sin((s / 100) * 2 * Math.PI)
    const brg = 150 + yaw // sotavento fixo + guinada
    const rad = (brg * Math.PI) / 180
    const bx = ax + Math.sin(rad) * swingR
    const by = ay + Math.cos(rad) * swingR
    // heading aponta para a âncora
    const heading = (Math.atan2(ax - bx, ay - by) * 180 / Math.PI + 360) % 360
    // antena atrás da proa 4 m
    const antX = bx - Math.sin(heading * Math.PI / 180) * 4
    const antY = by - Math.cos(heading * Math.PI / 180) * 4
    fixes.push({
      t: t0 + s * 1000,
      lat: origin.lat + antY / m.lat,
      lon: origin.lon + antX / m.lon,
      accuracy: 4,
      heading: +heading.toFixed(2),
      depth: 6,
    })
  }

  const watch = new AnchorWatch({ boatLength: 8, antennaToBow: 4, rodeLength: 40, depth: 6, autoFitAnchor: false })
  // marca a âncora na origem (proa projetada) usando o primeiro fix
  watch.dropAnchor(fixes[0])
  watch.arm()
  watch.armedAt = fixes[0].t

  const samples = []
  const sampleAt = new Set([60, 300, 600, 900, 1200, 1500, 1800, 2100, 2400, 2700, 3000, 3300, 3599])
  fixes.forEach((f, i) => {
    const snap = watch.feed(f)
    if (sampleAt.has(i)) {
      samples.push({
        i,
        state: snap.state,
        distance: +snap.distance.toFixed(3),
        bearing: +snap.bearing.toFixed(2),
        radius: +snap.radius.toFixed(3),
        driftRate: +snap.drift.rate.toFixed(4),
        driftAccum: +snap.drift.accumulated.toFixed(3),
        driftSig: snap.drift.significant,
      })
    }
  })
  out.trace = {
    config: { boatLength: 8, antennaToBow: 4, rodeLength: 40, depth: 6, autoFitAnchor: false },
    fixes,
    anchorDrop: 0, // índice do fix usado no dropAnchor
    samples,
    firstAlarmIndex: (() => {
      const w2 = new AnchorWatch({ boatLength: 8, antennaToBow: 4, rodeLength: 40, depth: 6, autoFitAnchor: false })
      w2.dropAnchor(fixes[0]); w2.arm(); w2.armedAt = fixes[0].t
      for (let i = 0; i < fixes.length; i++) { if (w2.feed(fixes[i]).state === 'alarm') return i }
      return -1
    })(),
  }
}

const dst = path.join(__dirname, 'test', 'golden.json')
fs.mkdirSync(path.dirname(dst), { recursive: true })
fs.writeFileSync(dst, JSON.stringify(out))
console.log('golden.json gerado:', dst)
console.log('  rng[0..2]:', out.rng.values.slice(0, 3))
console.log('  swing[0].radius:', out.swing[0].radius.toFixed(2), 'scope:', out.swing[0].scope.toFixed(2))
console.log('  fitCircle: centro', out.fitCircle.fit.x.toFixed(2), out.fitCircle.fit.y.toFixed(2), 'r', out.fitCircle.fit.r.toFixed(2), 'span', out.fitCircle.fit.span.toFixed(1))
console.log('  trace samples:', out.trace.samples.length, '· primeiro alarme no fix', out.trace.firstAlarmIndex)
console.log('  trace states:', out.trace.samples.map(s => s.i + ':' + s.state).join(' '))

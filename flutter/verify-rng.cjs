/* Valida que o port Dart do mulberry32 reproduz o JS bit-a-bit, emulando a
 * aritmética de int 64-bit do Dart com BigInt (o Dart mobile/native usa int
 * 64-bit). Se bater com o JS original, o RNG Dart está correto.
 */
const SBSim = require('../core/sim-device.js')

const M = 0xFFFFFFFFn
function toSigned32(x) { x &= M; return x >= 0x80000000n ? x - 0x100000000n : x }

// --- emulação EXATA do Mulberry32.next() do Dart, com BigInt ---
function dartImul(a, b) {
  a &= M; b &= M
  const ah = (a >> 16n) & 0xFFFFn, al = a & 0xFFFFn
  const bh = (b >> 16n) & 0xFFFFn, bl = b & 0xFFFFn
  const hi = ((ah * bl + al * bh) & M) << 16n
  return toSigned32((al * bl + hi) & M)
}
function dartMulberry(seed) {
  let _a = BigInt(seed) & M
  return function () {
    _a = (_a + 0x6D2B79F5n) & M
    const a = _a
    const t1 = dartImul(a ^ (a >> 15n), 1n | a)
    const u = t1 & M
    const inner = dartImul(u ^ (u >> 7n), 61n | u)
    const t = toSigned32(((t1 + inner) & M) ^ u)
    const tu = t & M
    return Number((tu ^ (tu >> 14n)) & M) / 4294967296
  }
}

// --- gauss idêntico (Box-Muller) sobre o RNG Dart ---
function dartGauss(rnd) {
  let u = 0, v = 0
  while (u === 0) u = rnd()
  while (v === 0) v = rnd()
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v)
}

let ok = true

// RNG: deve ser IDÊNTICO ao JS
for (const seed of [7, 42, 1000, 1481, 123456]) {
  const js = SBSim.mulberry32(seed)
  const dart = dartMulberry(seed)
  for (let i = 0; i < 20; i++) {
    const a = js(), b = dart()
    if (a !== b) { ok = false; console.log(`DIVERGE seed=${seed} i=${i}: js=${a} dart=${b}`) }
  }
}
console.log(ok ? 'RNG: Dart == JS (bit-a-bit) em 5 sementes x 20 valores ✓' : 'RNG: DIVERGÊNCIA ✗')

// gauss: idêntico se o RNG for idêntico (mesmas funções transcendentais no Node)
let gok = true
{
  const js = SBSim.mulberry32(42), dart = dartMulberry(42)
  for (let i = 0; i < 8; i++) {
    const a = SBSim.gauss(js), b = dartGauss(dart)
    if (Math.abs(a - b) > 1e-15) { gok = false; console.log(`gauss diverge i=${i}: ${a} vs ${b}`) }
  }
}
console.log(gok ? 'gauss: Dart == JS ✓' : 'gauss: DIVERGE ✗')

// confere contra o golden gravado
const golden = require('./test/golden.json')
const gr = dartMulberry(golden.rng.seed)
let match = true
golden.rng.values.forEach((v, i) => { const d = gr(); if (Math.abs(d - v) > 1e-15) { match = false; console.log(`golden rng[${i}] ${v} != ${d}`) } })
console.log(match ? 'golden.rng: reproduzido pelo port ✓' : 'golden.rng: NÃO reproduzido ✗')

process.exit(ok && gok && match ? 0 : 1)

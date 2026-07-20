/* SAFEBOAT — varredura de robustez da âncora virtual
 * ===================================================
 * Um cenário passar com uma semente não quer dizer nada. Aqui cada cenário roda
 * com N sementes diferentes e com dois tipos de barco (lancha, que fica quieta,
 * e veleiro, que veleja muito mais no fundeio), medindo:
 *   - taxa de falso alarme nos cenários benignos (tem que ser 0);
 *   - taxa de detecção nos cenários de garrar (tem que ser 100%);
 *   - quanto a âncora andou antes do alarme (quanto menor, melhor).
 *
 *   node test-sweep.cjs [nSementes]
 */
const { AnchorWatch, STATE } = require('./core/anchor-core.js')
const { SimulatedBoat, SCENARIOS } = require('./core/sim-device.js')

const N = parseInt(process.argv[2] || '12', 10)
const DUR_MIN = 90
const BENIGNOS = ['calma', 'rajadas', 'ronda-vento', 'mare', 'multipath', 'poita', 'perda-sinal']
const GARRANDO = ['garrando', 'garrando-lento', 'poita-rompida']

function run(name, seed, windage) {
  const sc = SCENARIOS[name]
  const mooring = !!sc.mooring
  const boat = new SimulatedBoat({ scenario: name, seed, rodeLength: mooring ? 12 : 40, depth: 6, boatLength: 8, antennaToBow: 4, windage })
  const watch = new AnchorWatch({ boatLength: 8, antennaToBow: 4, rodeLength: mooring ? 12 : 40, depth: 6, alarmRadius: mooring ? 22 : null })
  let fix = null
  for (let i = 0; i < 120; i++) fix = boat.step(1)
  watch.setAnchor(boat.truthAnchorLatLon(), 'marcado')
  watch.arm(); watch.armedAt = fix.t
  let alarmMin = null, alarmDrag = null, preMin = null
  for (let i = 0; i < DUR_MIN * 60; i++) {
    fix = boat.step(1)
    const s = watch.feed(fix)
    const min = (fix.t - watch.armedAt) / 60000
    if (s.state === STATE.PREALARM && preMin == null) preMin = min
    if (s.state === STATE.ALARM && alarmMin == null) { alarmMin = min; alarmDrag = fix.truth.dragged }
  }
  return { alarmMin, alarmDrag, preMin }
}

console.log(`\n\x1b[1mSAFEBOAT — varredura de robustez\x1b[0m`)
console.log(`${N} sementes x 2 tipos de barco (lancha / veleiro) x ${DUR_MIN} min\n`)

let totalFalse = 0, totalBenign = 0, totalMissed = 0, totalDrag = 0

console.log('\x1b[2m  cenário                    falso alarme    atenção     detecção      garrou até\x1b[0m')
for (const name of [...BENIGNOS, ...GARRANDO]) {
  const benigno = BENIGNOS.includes(name)
  let falso = 0, det = 0, runs = 0, sumDrag = 0, sumMin = 0, pre = 0
  for (const windage of [1, 1.4]) {
    for (let s = 0; s < N; s++) {
      const r = run(name, 1000 + s * 37, windage)
      runs++
      if (r.preMin != null) pre++
      if (benigno) { if (r.alarmMin != null) falso++ }
      else if (r.alarmMin != null) { det++; sumDrag += r.alarmDrag; sumMin += r.alarmMin }
    }
  }
  if (benigno) {
    totalBenign += runs; totalFalse += falso
    const tag = falso === 0 ? '\x1b[32m' : '\x1b[31m'
    console.log(`  ${SCENARIOS[name].nome.padEnd(26)} ${tag}${String(falso).padStart(2)}/${runs}\x1b[0m         ${String(pre).padStart(2)}/${runs}          —             —`)
  } else {
    totalMissed += runs - det; totalDrag += sumDrag
    const tag = det === runs ? '\x1b[32m' : '\x1b[31m'
    console.log(`  ${SCENARIOS[name].nome.padEnd(26)}  —            ${String(pre).padStart(2)}/${runs}        ${tag}${String(det).padStart(2)}/${runs}\x1b[0m       ${det ? (sumDrag / det).toFixed(0) + ' m em ' + (sumMin / det).toFixed(0) + ' min' : '—'}`)
  }
}

console.log(`\n  falsos alarmes: \x1b[1m${totalFalse}/${totalBenign}\x1b[0m   ·   garradas não detectadas: \x1b[1m${totalMissed}\x1b[0m\n`)
process.exit(totalFalse || totalMissed ? 1 : 0)

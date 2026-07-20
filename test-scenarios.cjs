/* SAFEBOAT — Bancada de simulação da âncora virtual
 * ==================================================
 * Roda todos os cenários de cabo a rabo e verifica o comportamento esperado do
 * detector: os cenários benignos NÃO podem alarmar, os de garrando TÊM que
 * alarmar, e rápido. É o teste que dá confiança para levar isso a bordo.
 *
 *   node test-scenarios.cjs              # todos os cenários
 *   node test-scenarios.cjs garrando     # um cenário, com detalhes
 */
const { AnchorWatch, STATE } = require('./core/anchor-core.js')
const { SimulatedBoat, SCENARIOS } = require('./core/sim-device.js')

const DUR_MIN = 90        // duração simulada de cada cenário
const HZ = 1              // taxa de amostragem do SAFEBOAT

// o que esperamos de cada cenário: alarme ou não, e em quanto tempo
const EXPECT = {
  'calma':          { alarm: false },
  'rajadas':        { alarm: false },
  'ronda-vento':    { alarm: false },
  'mare':           { alarm: false },
  'multipath':      { alarm: false },
  'poita':          { alarm: false },
  'perda-sinal':    { alarm: false, expectNoSignal: true },
  'garrando':       { alarm: true, dragStartsMin: 12, maxDetectMin: 8, maxDistM: 25 },
  'garrando-lento': { alarm: true, dragStartsMin: 10, maxDetectMin: 30, maxDistM: 20 },
  'poita-rompida':  { alarm: true, dragStartsMin: 15, maxDetectMin: 4,  maxDistM: 40 },
}

function runScenario(name, opts) {
  const o = opts || {}
  const sc = SCENARIOS[name]
  const mooring = !!sc.mooring
  const boat = new SimulatedBoat({
    scenario: name,
    seed: o.seed != null ? o.seed : 7,
    rodeLength: mooring ? 12 : 40,
    depth: 6,
    boatLength: 8,
    antennaToBow: 4,
    windage: o.windage != null ? o.windage : 1,
  })

  const watch = new AnchorWatch({
    boatLength: 8, antennaToBow: 4,
    rodeLength: mooring ? 12 : 40,
    depth: 6,
    alarmRadius: mooring ? 22 : null,
  })

  // deixa o barco assentar antes de marcar a âncora (como na vida real: fundeia,
  // dá ré para cravar, e só então liga o alarme)
  let fix = null
  for (let i = 0; i < 120 * HZ; i++) fix = boat.step(1 / HZ)

  // marca a âncora na posição VERDADEIRA dela (usuário aperta o botão no
  // lançamento) com o errinho normal de alguns segundos de atraso
  const truth = boat.truthAnchorLatLon()
  watch.setAnchor(truth, 'marcado')
  watch.arm()
  watch.armedAt = fix.t

  const timeline = []
  let firstAlarm = null, firstPre = null, sawNoSignal = false
  let alarmAtDist = null, falseAlarms = 0, lastState = STATE.ARMED

  const steps = DUR_MIN * 60 * HZ
  for (let i = 0; i < steps; i++) {
    fix = boat.step(1 / HZ)
    const snap = watch.feed(fix)
    const min = (fix.t - watch.armedAt) / 60000

    if (snap.state !== lastState) {
      timeline.push({ min: +min.toFixed(1), from: lastState, to: snap.state, dist: +snap.distance.toFixed(1), drift: +snap.drift.dist.toFixed(1) })
      lastState = snap.state
    }
    if (snap.state === STATE.NOSIGNAL) sawNoSignal = true
    if (snap.state === STATE.PREALARM && firstPre == null) firstPre = min
    if (snap.state === STATE.ALARM && firstAlarm == null) {
      firstAlarm = min
      alarmAtDist = fix.truth.dragged   // quantos metros a âncora já andou de verdade
    }
  }

  return {
    name, sc, timeline, firstAlarm, firstPre, sawNoSignal, alarmAtDist,
    maxDist: Math.max(...watch.track.map(p => p.r)),
    radius: watch.radius,
    truthDragged: boat.truth ? 0 : Math.hypot(boat.anchor.x, boat.anchor.y),
    anchorError: haversine(watch.anchor, boat.truthAnchorLatLon()),
    watch, boat,
  }
}

function haversine(a, b) {
  if (!a || !b) return 0
  const R = 6371008.8, D = Math.PI / 180
  const dLat = (b.lat - a.lat) * D, dLon = (b.lon - a.lon) * D
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * D) * Math.cos(b.lat * D) * Math.sin(dLon / 2) ** 2
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)))
}

function judge(r) {
  const exp = EXPECT[r.name]
  if (!exp) return { ok: true, note: 'sem expectativa definida' }
  const notes = []
  let ok = true

  if (exp.alarm) {
    if (r.firstAlarm == null) { ok = false; notes.push('NÃO alarmou (deveria)') }
    else {
      const detectMin = r.firstAlarm - (exp.dragStartsMin - 2)
      if (detectMin > exp.maxDetectMin) { ok = false; notes.push(`demorou ${detectMin.toFixed(1)} min (limite ${exp.maxDetectMin})`) }
      else notes.push(`detectou em ${Math.max(0, detectMin).toFixed(1)} min`)
      if (exp.maxDistM && r.alarmAtDist > exp.maxDistM) { ok = false; notes.push(`âncora já tinha andado ${r.alarmAtDist.toFixed(0)} m (limite ${exp.maxDistM})`) }
      else if (r.alarmAtDist != null) notes.push(`âncora andou ${r.alarmAtDist.toFixed(0)} m até o alarme`)
    }
  } else {
    if (r.firstAlarm != null) { ok = false; notes.push(`FALSO ALARME aos ${r.firstAlarm.toFixed(1)} min`) }
    else notes.push('nenhum alarme (correto)')
    if (r.firstPre != null) notes.push(`atenção aos ${r.firstPre.toFixed(1)} min`)
  }
  if (exp.expectNoSignal && !r.sawNoSignal) { ok = false; notes.push('não sinalizou perda de GPS') }
  return { ok, note: notes.join(' · ') }
}

// ------------------------------------------------------------------- saída

const only = process.argv[2]
const names = only ? [only] : Object.keys(SCENARIOS)
let pass = 0, fail = 0

console.log('\n\x1b[1mSAFEBOAT — bancada da âncora virtual\x1b[0m')
console.log(`${DUR_MIN} min simulados por cenário · amostragem ${HZ} Hz\n`)

for (const name of names) {
  if (!SCENARIOS[name]) { console.log(`cenário desconhecido: ${name}`); process.exit(1) }
  const r = runScenario(name)
  const v = judge(r)
  v.ok ? pass++ : fail++
  const tag = v.ok ? '\x1b[32m  OK  \x1b[0m' : '\x1b[31m FALHA\x1b[0m'
  console.log(`${tag} \x1b[1m${r.sc.nome}\x1b[0m  (raio ${r.radius.toFixed(0)} m, máx. atingido ${r.maxDist.toFixed(0)} m)`)
  console.log(`        ${v.note}`)
  if (only) {
    console.log(`        erro de posição da âncora: ${r.anchorError.toFixed(1)} m`)
    console.log('\n        transições:')
    for (const t of r.timeline) console.log(`          ${String(t.min).padStart(6)} min  ${t.from} → ${t.to}   dist ${t.dist} m, deriva do centro ${t.drift} m`)
    console.log('\n        eventos:')
    for (const e of r.watch.events) console.log(`          ${e.kind.padEnd(12)} ${e.text}`)
  }
  console.log('')
}

console.log(`\x1b[1m${pass} passou, ${fail} falhou\x1b[0m\n`)
process.exit(fail ? 1 : 0)

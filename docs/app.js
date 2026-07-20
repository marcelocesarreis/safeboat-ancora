/* SAFEBOAT — Âncora Virtual — lógica do protótipo
 * ================================================
 * Amarra o núcleo (SBAnchor), o dispositivo simulado (SBDevice) e a UI. Toda a
 * decisão de alarme vem do núcleo — esta camada só desenha e traduz cliques.
 * Trocar SimAdapter por SafeboatAdapter (device-adapter.js) conecta o barco
 * real sem tocar em nada aqui.
 */
'use strict'

const { AnchorWatch, STATE, swingRadius, scopeRatio, toLocal, fromLocal, destination } = SBAnchor
const { SCENARIOS } = SBSim

// ------------------------------------------------------------------- estado

let cfg = { boatLength: 8, antennaToBow: 4, rodeLength: 40, depth: 6, bowRoller: 1.2, gpsMargin: 5 }
let watch = new AnchorWatch(cfg)
let adapter = SBDevice.makeAdapter({ scenario: 'calma', speed: 60, boatLength: cfg.boatLength, antennaToBow: cfg.antennaToBow, rodeLength: cfg.rodeLength, depth: cfg.depth })
let scenario = 'calma'
let speed = 60
let playing = true
let lastFix = null
let armed = false
let viewSpan = 140       // metros de largura do mapa (zoom)
let toastShown = false
let pendingRadius = null

const STATE_LABELS = {
  idle:     { sub: 'Âncora não lançada',          main: 'Alarme de âncora inativo',  cls: 'idle',     tag: ['grey', 'Inativo'] },
  setting:  { sub: 'Verificando aguante',          main: 'Cravando a âncora…',        cls: 'idle',     tag: ['amber', 'Testando'] },
  armed:    { sub: 'Vigiando o fundeio',           main: 'Alarme de âncora Ativo',    cls: '',         tag: ['green', 'Protegido'] },
  prealarm: { sub: 'Atenção',                       main: 'Encostando no limite',      cls: 'pre',      tag: ['amber', 'Atenção'] },
  alarm:    { sub: 'EMERGÊNCIA',                    main: 'GARRANDO — barco à deriva', cls: 'alarm',    tag: ['red', 'Garrando'] },
  nosignal: { sub: 'Sinal de GPS ruim',            main: 'Vigília em dúvida',         cls: 'nosignal', tag: ['grey', 'Sem GPS'] },
}

// ------------------------------------------------------------ inicialização

function boot() {
  buildScenarioBar()
  buildSpeedButtons()
  // pré-enche ~2 min de rastro para o mapa já nascer com movimento
  adapter.warmup(90)
  renderActions()
  adapter.start(onFix)
  setInterval(tickClock, 1000)
}

function tickClock() {
  if (!lastFix) return
  const d = new Date(lastFix.t)
  document.getElementById('clock').textContent =
    String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0')
}

// -------------------------------------------------------------- loop de fix

let lastRenderAt = 0
let pendingSnap = null
function onFix(fix) {
  lastFix = fix
  const snap = watch.feed(fix)   // núcleo decide tudo (sempre, a cada fix)
  pendingSnap = snap
  // desacopla o desenho da simulação: o núcleo processa todo fix, mas o mapa SVG
  // só é redesenhado ~12x/s. Em 60×/120× isso evita saturar o renderizador sem
  // perder nenhuma decisão de alarme (que acontece no feed, não no render).
  const now = performance.now ? performance.now() : Date.now()
  if (now - lastRenderAt >= 80) { lastRenderAt = now; render(snap, fix) }
}

// ------------------------------------------------------------------ simulador

function buildScenarioBar() {
  const row = document.getElementById('scenRow')
  row.innerHTML = ''
  const danger = new Set(['garrando', 'garrando-lento', 'poita-rompida'])
  for (const [key, sc] of Object.entries(SCENARIOS)) {
    const b = document.createElement('button')
    b.className = 'scen' + (danger.has(key) ? ' danger' : '') + (key === scenario ? ' active' : '')
    b.textContent = sc.nome
    b.onclick = () => selectScenario(key)
    row.appendChild(b)
  }
  document.getElementById('scenDesc').textContent = SCENARIOS[scenario].desc
}

function selectScenario(key) {
  scenario = key
  adapter.setScenario(key)
  // reinicia a vigília: cada cenário é um novo fundeio
  armed = false
  toastShown = false
  hideToast()
  watch = new AnchorWatch(cfg)
  adapter.warmup(90)
  buildScenarioBar()
  renderActions()
}

function buildSpeedButtons() {
  const row = document.getElementById('spdRow')
  row.innerHTML = ''
  for (const s of [30, 60, 120]) {
    const b = document.createElement('button')
    b.textContent = s + '×'
    b.className = s === speed ? 'on' : ''
    b.onclick = () => { speed = s; adapter.stop(); adapter.speed = s; adapter.start(onFix); buildSpeedButtons() }
    row.appendChild(b)
  }
}

function togglePlay() {
  playing = !playing
  if (playing) adapter.start(onFix); else adapter.stop()
  document.getElementById('playBtn').textContent = playing ? '⏸ Pausar' : '▶ Continuar'
}

function restart() { selectScenario(scenario) }

// -------------------------------------------------------------------- ações

function renderActions() {
  const el = document.getElementById('actions')
  const st = watch.state
  if (st === 'idle' && !armed) {
    el.innerHTML = `<button class="pill-btn solid" onclick="openSheet()">⚓ ATIVAR ALARME</button>`
  } else if (st === 'setting') {
    el.innerHTML = `
      <div class="cfg-note" style="margin:14px 0 0">
        <span>⚙️</span>
        <span>Dê ré devagar contra a âncora para cravá-la. O SAFEBOAT confirma o aguante pelo esforço da amarra. Quando estiver seguro, ative a vigília.</span>
      </div>
      <button class="pill-btn green" onclick="finishSetting()">Âncora cravada — vigiar</button>`
  } else if (st === 'alarm' || st === 'prealarm') {
    el.innerHTML = `<div class="btn-row">
        <button class="pill-btn" onclick="ack()">Reconhecer</button>
        <button class="pill-btn ghost-red" onclick="disarm()">Desativar</button>
      </div>`
  } else {
    el.innerHTML = `<button class="pill-btn ghost-red" onclick="disarm()">🔕 DESATIVAR ALARME</button>`
  }
}

function finishSetting() { armed = true; watch.arm(); renderActions() }

function disarm() {
  watch.disarm(); armed = false; toastShown = false; hideToast(); renderActions()
}

function ack() { watch.acknowledge(); hideToast(); toastShown = false; renderActions() }

// --------------------------------------------------------- bottom sheet raio

function openSheet() {
  syncSheetInputs()
  updateSheet()
  document.getElementById('sheetBack').classList.add('on')
  document.getElementById('sheet').classList.add('on')
}
function closeSheet() {
  document.getElementById('sheetBack').classList.remove('on')
  document.getElementById('sheet').classList.remove('on')
}

function syncSheetInputs() {
  document.getElementById('fRode').value = cfg.rodeLength
  document.getElementById('fDepth').value = cfg.depth
  document.getElementById('fBoat').value = cfg.boatLength
  document.getElementById('fMargin').value = cfg.gpsMargin
  ;['fRode', 'fDepth', 'fBoat', 'fMargin'].forEach(id => {
    document.getElementById(id).oninput = () => { readSheetInputs(); updateSheet() }
  })
}
function readSheetInputs() {
  cfg.rodeLength = +document.getElementById('fRode').value || 0
  cfg.depth = +document.getElementById('fDepth').value || 0
  cfg.boatLength = +document.getElementById('fBoat').value || 0
  cfg.gpsMargin = +document.getElementById('fMargin').value || 0
  pendingRadius = null   // volta a seguir o cálculo automático
}

function updateSheet() {
  const auto = swingRadius(cfg)
  const r = pendingRadius != null ? pendingRadius : auto
  const scope = scopeRatio(cfg)
  document.getElementById('scopeVal').textContent = scope.toFixed(1).replace('.', ',') + ':1'
  document.getElementById('radiusLbl').textContent = Math.round(r) + ' m'
  const slider = document.getElementById('radiusSlider')
  slider.value = Math.round(r)
  slider.style.setProperty('--pct', ((r - 15) / (120 - 15) * 100) + '%')
  drawMiniMap(r, auto)
}

function onRadiusInput(v) {
  pendingRadius = +v
  document.getElementById('radiusLbl').textContent = Math.round(v) + ' m'
  document.getElementById('radiusSlider').style.setProperty('--pct', ((v - 15) / (120 - 15) * 100) + '%')
  drawMiniMap(+v, swingRadius(cfg))
}

function confirmArm() {
  readSheetInputs()
  watch.setConfig(Object.assign({}, cfg, { alarmRadius: pendingRadius }))
  // âncora na posição atual do barco, projetada para a proa (lançamento agora)
  if (lastFix) watch.dropAnchor(lastFix)
  closeSheet()
  renderActions()
}

// ------------------------------------------------------------------ render

function render(snap, fix) {
  const lbl = STATE_LABELS[snap.state] || STATE_LABELS.idle
  document.getElementById('stateSub').textContent = snap.state === 'armed' ? `Dentro do raio de ${Math.round(snap.radius)} m` : lbl.sub
  document.getElementById('stateMain').textContent = lbl.main
  const icon = document.getElementById('stateIcon')
  icon.className = 'icon-circle ' + lbl.cls

  drawMap(snap, fix)
  drawMetrics(snap)
  drawEvents()
  document.getElementById('simTime').textContent = 't+' + Math.round((fix.t - adapter.boat.t0) / 60000) + ' min'
  document.getElementById('scenDesc').textContent = SCENARIOS[scenario].desc

  // badges do mapa
  document.getElementById('badgeDist').innerHTML =
    `<span class="k">dist.</span> <b>${snap.anchor ? Math.round(snap.distance) + ' m' : '—'}</b>`
  const acc = fix.accuracy
  const gcls = acc > 25 ? 'red' : acc > 12 ? 'amber' : 'green'
  document.getElementById('badgeGps').innerHTML =
    `<span class="k">GPS</span> <b style="color:${gcls === 'red' ? '#ff8f88' : gcls === 'amber' ? '#FFD738' : '#A5CB74'}">±${Math.round(acc)} m</b>`

  // toast de alarme
  if (snap.state === 'alarm' && !toastShown) {
    showToast(snap)
    toastShown = true
    renderActions()
  } else if (snap.state !== 'alarm' && snap.state !== 'prealarm') {
    if (toastShown) { toastShown = false; renderActions() }
  }
  // mantém os botões coerentes com o estado
  syncActionButtons(snap.state)
}

let lastActionState = null
function syncActionButtons(st) {
  if (st !== lastActionState) { lastActionState = st; renderActions() }
}

function showToast(snap) {
  const t = document.getElementById('toast')
  document.getElementById('toastT1').textContent = 'ALARME DE ÂNCORA'
  const ev = watch.events.filter(e => e.kind === 'alarme').slice(-1)[0]
  document.getElementById('toastT2').textContent = ev ? ev.text.replace('GARRANDO — ', '') : 'O barco está garrando'
  t.classList.add('on')
  // vibra o telefone (onde o navegador permitir) — simula o buzzer do SAFEBOAT
  if (navigator.vibrate) navigator.vibrate([200, 100, 200, 100, 400])
}
function hideToast() { document.getElementById('toast').classList.remove('on') }

// ------------------------------------------------------------- métricas

function drawMetrics(snap) {
  const el = document.getElementById('metrics')
  if (!snap.anchor) {
    el.innerHTML = `<div class="metric wide" style="justify-content:center;color:var(--muted);font-size:13px">
      Lance a âncora e ative o alarme para começar a vigília.</div>`
    return
  }
  const scope = snap.scope
  const drift = snap.drift
  const driftTxt = drift && drift.significant
    ? `${drift.rate.toFixed(2)} <small>m/min</small>`
    : `estável`
  const driftCls = drift && drift.significant ? 'style="color:#ff8f88"' : ''
  el.innerHTML = `
    <div class="metric"><div class="k">Distância</div><div class="v">${Math.round(snap.distance)} <small>m</small></div></div>
    <div class="metric"><div class="k">Raio</div><div class="v">${Math.round(snap.radius)} <small>m</small></div></div>
    <div class="metric"><div class="k">Rumo p/ âncora</div><div class="v">${Math.round((snap.bearing + 180) % 360)}<small>°</small></div></div>
    <div class="metric"><div class="k">Scope</div><div class="v">${scope.toFixed(1)}<small>:1</small></div></div>
    <div class="metric"><div class="k">Prof.</div><div class="v">${snap.depth ? snap.depth.toFixed(1) : '—'} <small>m</small></div></div>
    <div class="metric"><div class="k">Deriva centro</div><div class="v" ${driftCls}>${driftTxt}</div></div>
    <div class="metric wide">
      <span style="font-size:11px;color:var(--muted);font-weight:600;white-space:nowrap">USO DO RAIO</span>
      <div class="gauge">
        <div class="fill" style="width:${Math.min(100, snap.usage * 100).toFixed(0)}%;background:${gaugeColor(snap.usage)}"></div>
        <div class="mark" style="left:${(snap.maxRadiusSeen / snap.radius * 100).toFixed(0)}%"></div>
      </div>
      <span style="font-size:12px;font-weight:700;white-space:nowrap">${Math.round(snap.usage * 100)}%</span>
    </div>`
}
function gaugeColor(u) { return u > 1 ? '#E0524B' : u > 0.85 ? '#FFD738' : '#A5CB74' }

// -------------------------------------------------------------- histórico

function drawEvents() {
  const el = document.getElementById('events')
  const evs = watch.events.slice(-8).reverse()
  document.getElementById('evtCount').textContent = watch.events.length + ' eventos'
  const icons = { alarme: '⚠️', atencao: '👀', armado: '⚓', desarmado: '🔕', ancora: '⚓', normal: '✓', reconhecido: '👍', sinal: '📡', reconhecido: '👍' }
  el.innerHTML = evs.map(e => {
    const d = new Date(e.t)
    const hh = String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0')
    return `<div class="event ${e.kind}">
      <div class="ico">${icons[e.kind] || '•'}</div>
      <div class="txt">${e.text}</div>
      <div class="time">${hh}</div>
    </div>`
  }).join('') || `<div style="color:var(--muted);font-size:13px;padding:8px 2px">Nenhum evento ainda.</div>`
}

// ---------------------------------------------------------------- mapa SVG

function zoom(f) { viewSpan = Math.max(50, Math.min(600, viewSpan / f)); if (lastFix) render(watch.snapshot(), lastFix) }

function drawMap(snap, fix) {
  const svg = document.getElementById('map')
  const S = 400
  // centro do mapa: âncora se existir, senão o barco
  const truthAnchor = adapter.boat ? adapter.boat.truthAnchorLatLon() : null
  const center = snap.anchor || snap.position || { lat: fix.lat, lon: fix.lon }
  const mpp = viewSpan / S   // metros por pixel
  const ref = center
  const P = (ll) => {
    const l = toLocal(ref, ll)
    return { x: S / 2 + l.x / mpp, y: S / 2 - l.y / mpp }
  }

  let out = `<rect width="${S}" height="${S}" fill="var(--water)"/>`
  // grade sutil
  out += `<g stroke="rgba(255,255,255,.05)" stroke-width="1">`
  for (let i = 1; i < 8; i++) out += `<line x1="${i * S / 8}" y1="0" x2="${i * S / 8}" y2="${S}"/><line x1="0" y1="${i * S / 8}" x2="${S}" y2="${i * S / 8}"/>`
  out += `</g>`

  if (snap.anchor) {
    const a = P(snap.anchor)
    const rPx = snap.radius / mpp

    // círculo de raio (tracejado, cor pelo estado)
    const ringColor = snap.state === 'alarm' ? '#E0524B' : snap.state === 'prealarm' ? '#FFD738' : '#A5CB74'
    out += `<circle cx="${a.x}" cy="${a.y}" r="${rPx}" fill="${ringColor}" fill-opacity="0.07" stroke="${ringColor}" stroke-width="2.5" stroke-dasharray="7 7"/>`
    // anel de pré-alarme (85%)
    out += `<circle cx="${a.x}" cy="${a.y}" r="${rPx * 0.85}" fill="none" stroke="rgba(255,255,255,.18)" stroke-width="1" stroke-dasharray="3 6"/>`

    // rastro (breadcrumb) — o recurso mais elogiado nas reviews
    const track = watch.trackLatLon(500)
    if (track.length > 1) {
      let d = ''
      track.forEach((p, i) => { const q = P(p); d += (i ? 'L' : 'M') + q.x.toFixed(1) + ' ' + q.y.toFixed(1) })
      out += `<path d="${d}" fill="none" stroke="#bfe0ff" stroke-opacity="0.55" stroke-width="1.6" stroke-linejoin="round"/>`
      // pontos recentes mais vivos
      const recent = track.slice(-40)
      recent.forEach((p, i) => { const q = P(p); out += `<circle cx="${q.x.toFixed(1)}" cy="${q.y.toFixed(1)}" r="1.6" fill="#eaf4ff" fill-opacity="${(0.15 + 0.75 * i / recent.length).toFixed(2)}"/>` })
    }

    // linha da amarra âncora→barco
    if (snap.position) {
      const b = P(snap.position)
      out += `<line x1="${a.x}" y1="${a.y}" x2="${b.x}" y2="${b.y}" stroke="rgba(255,255,255,.35)" stroke-width="1.5" stroke-dasharray="2 4"/>`
    }

    // seta de deriva do centro (quando garrando)
    if (snap.drift && snap.drift.significant && snap.drift.accumulated > 3) {
      const len = Math.min(rPx * 0.9, snap.drift.accumulated / mpp * 3)
      const dr = snap.drift.brg * Math.PI / 180
      const ex = a.x + Math.sin(dr) * len, ey = a.y - Math.cos(dr) * len
      out += `<line x1="${a.x}" y1="${a.y}" x2="${ex}" y2="${ey}" stroke="#E0524B" stroke-width="2.5"/>`
      out += `<circle cx="${ex}" cy="${ey}" r="4" fill="#E0524B"/>`
    }

    // pino da âncora
    out += anchorPin(a.x, a.y)

    // "âncora real" da simulação (fantasma) — para comparar visualmente com a estimada
    if (truthAnchor) {
      const ta = P(truthAnchor)
      const dd = Math.hypot(ta.x - a.x, ta.y - a.y)
      if (dd > 3) out += `<circle cx="${ta.x}" cy="${ta.y}" r="5" fill="none" stroke="#fff" stroke-opacity=".4" stroke-width="1.5" stroke-dasharray="2 3"/><text x="${ta.x + 8}" y="${ta.y + 3}" fill="#fff" fill-opacity=".5" font-size="9">âncora real</text>`
    }
  }

  // barco (na posição atual, orientado pela proa)
  const bp = snap.position || { lat: fix.lat, lon: fix.lon }
  const b = P(bp)
  out += boatIcon(b.x, b.y, fix.heading || 0, snap.state)

  svg.innerHTML = out
}

function anchorPin(x, y) {
  return `<g transform="translate(${x},${y})">
    <circle r="13" fill="#1E2A49" stroke="#A5CB74" stroke-width="2"/>
    <g transform="translate(-7,-7) scale(0.58)" stroke="#A5CB74" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round">
      <path d="M12 22V8M12 8a2 2 0 100-4 2 2 0 000 4zM5 12H2a10 10 0 0020 0h-3"/></g>
  </g>`
}

function boatIcon(x, y, heading, state) {
  const color = state === 'alarm' ? '#E0524B' : '#fff'
  return `<g transform="translate(${x},${y}) rotate(${heading})">
    <ellipse rx="7" ry="14" fill="#0e1526" fill-opacity="0.35" transform="translate(0,2)"/>
    <path d="M0 -15 C6 -9 7 6 4 14 L-4 14 C-7 6 -6 -9 0 -15 Z" fill="${color}" stroke="#1E2A49" stroke-width="1.5"/>
    <circle cx="0" cy="-2" r="2.4" fill="#1E2A49"/>
  </g>`
}

// -------------------------------------------------------- mini-mapa do sheet

function drawMiniMap(radius, autoRadius) {
  const svg = document.getElementById('miniMap')
  const W = 400, H = 275
  const cx = W / 2, cy = H / 2
  const scale = (H * 0.42) / Math.max(radius, autoRadius, 20)
  const rPx = radius * scale
  let out = `<rect width="${W}" height="${H}" fill="var(--water)"/>`
  out += `<circle cx="${cx}" cy="${cy}" r="${rPx}" fill="#A5CB74" fill-opacity="0.10" stroke="#A5CB74" stroke-width="2.5" stroke-dasharray="7 7"/>`
  // limite físico da amarra (o que a amarra explica), para o usuário ver a folga
  const physical = swingRadius(Object.assign({}, cfg, { gpsMargin: 0 })) * scale
  if (physical < rPx) out += `<circle cx="${cx}" cy="${cy}" r="${physical}" fill="none" stroke="rgba(255,255,255,.25)" stroke-width="1" stroke-dasharray="3 5"/>`
  out += anchorPin(cx, cy)
  out += boatIcon(cx, cy - rPx * 0.7, 0, 'armed')
  out += `<text x="${cx}" y="${cy + rPx + 18}" fill="#fff" fill-opacity=".7" font-size="12" text-anchor="middle">raio ${Math.round(radius)} m</text>`
  svg.innerHTML = out
}

// -------------------------------------------------------------------- go

boot()

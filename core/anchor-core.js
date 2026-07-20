/* SAFEBOAT — Núcleo da Âncora Virtual
 * =====================================
 * Puro: sem I/O, sem DOM, sem dependência. Roda igual no navegador (protótipo),
 * no Node (servidor/simulação) e serve de referência para portar ao firmware do
 * SAFEBOAT e ao app Flutter.
 *
 * Diferença de projeto em relação aos apps de celular (Anchor Pro, Anchor!, Drag
 * Queen, etc.): o SAFEBOAT é um dispositivo FIXO A BORDO. Isso muda tudo:
 *   - a antena não sai do barco quando o dono desce em terra;
 *   - o rastro é contínuo, então dá para ESTIMAR a posição da âncora ajustando
 *     um círculo ao arco de giro (nenhum app de celular consegue fazer isso bem,
 *     porque o celular só está a bordo às vezes);
 *   - o offset antena→proa é conhecido e fixo (calibração de instalação);
 *   - o alarme é avaliado a bordo 24/7 e só a NOTIFICAÇÃO viaja para o celular.
 */
(function (root, factory) {
  const api = factory()
  if (typeof module === 'object' && module.exports) module.exports = api
  root.SBAnchor = api
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict'

  // ---------------------------------------------------------------- geometria

  const R_EARTH = 6371008.8
  const D2R = Math.PI / 180
  const R2D = 180 / Math.PI

  /** metros por grau de latitude / longitude na latitude dada */
  function metersPerDegree(lat) {
    return { lat: 111132.92 - 559.82 * Math.cos(2 * lat * D2R), lon: 111412.84 * Math.cos(lat * D2R) }
  }

  /** lat/lon -> plano local ENU (x=leste, y=norte, em metros) com origem em `ref` */
  function toLocal(ref, p) {
    const m = metersPerDegree(ref.lat)
    return { x: (p.lon - ref.lon) * m.lon, y: (p.lat - ref.lat) * m.lat }
  }

  /** plano local ENU -> lat/lon */
  function fromLocal(ref, v) {
    const m = metersPerDegree(ref.lat)
    return { lat: ref.lat + v.y / m.lat, lon: ref.lon + v.x / m.lon }
  }

  /** distância em metros entre duas coordenadas (haversine) */
  function distance(a, b) {
    const dLat = (b.lat - a.lat) * D2R
    const dLon = (b.lon - a.lon) * D2R
    const la1 = a.lat * D2R, la2 = b.lat * D2R
    const h = Math.sin(dLat / 2) ** 2 + Math.cos(la1) * Math.cos(la2) * Math.sin(dLon / 2) ** 2
    return 2 * R_EARTH * Math.asin(Math.min(1, Math.sqrt(h)))
  }

  /** rumo verdadeiro de a para b, em graus 0..360 */
  function bearing(a, b) {
    const dLon = (b.lon - a.lon) * D2R
    const la1 = a.lat * D2R, la2 = b.lat * D2R
    const y = Math.sin(dLon) * Math.cos(la2)
    const x = Math.cos(la1) * Math.sin(la2) - Math.sin(la1) * Math.cos(la2) * Math.cos(dLon)
    return (Math.atan2(y, x) * R2D + 360) % 360
  }

  /** desloca uma coordenada por distância (m) num rumo (graus) */
  function destination(p, dist, brg) {
    const m = metersPerDegree(p.lat)
    const rad = brg * D2R
    return { lat: p.lat + (dist * Math.cos(rad)) / m.lat, lon: p.lon + (dist * Math.sin(rad)) / m.lon }
  }

  /** diferença angular assinada a-b em -180..180 */
  function angleDiff(a, b) {
    let d = ((a - b + 540) % 360) - 180
    return d
  }

  // ------------------------------------------------------- ajuste de círculo

  /** resolve sistema linear 3x3 por eliminação de Gauss com pivotamento */
  function solve3(A, b) {
    const M = [[A[0][0], A[0][1], A[0][2], b[0]], [A[1][0], A[1][1], A[1][2], b[1]], [A[2][0], A[2][1], A[2][2], b[2]]]
    for (let i = 0; i < 3; i++) {
      let piv = i
      for (let r = i + 1; r < 3; r++) if (Math.abs(M[r][i]) > Math.abs(M[piv][i])) piv = r
      if (Math.abs(M[piv][i]) < 1e-12) return null
      ;[M[i], M[piv]] = [M[piv], M[i]]
      for (let r = 0; r < 3; r++) {
        if (r === i) continue
        const f = M[r][i] / M[i][i]
        for (let c = i; c < 4; c++) M[r][c] -= f * M[i][c]
      }
    }
    return [M[0][3] / M[0][0], M[1][3] / M[1][1], M[2][3] / M[2][2]]
  }

  /**
   * Ajuste algébrico de círculo (Kåsa) a pontos {x,y} do plano local.
   * Retorna {x,y,r,rms,span} ou null. `span` é a cobertura angular do arco em
   * graus — abaixo de ~70° o ajuste é mal-condicionado e NÃO deve ser usado
   * para reposicionar a âncora (um arco curto cabe em infinitos círculos).
   */
  function fitCircle(pts) {
    const n = pts.length
    if (n < 8) return null
    let sx = 0, sy = 0
    for (const p of pts) { sx += p.x; sy += p.y }
    const cx0 = sx / n, cy0 = sy / n
    // centraliza para condicionar melhor o sistema
    let Sxx = 0, Sxy = 0, Syy = 0, Sxz = 0, Syz = 0, Sx = 0, Sy = 0, Sz = 0
    for (const p of pts) {
      const x = p.x - cx0, y = p.y - cy0, z = x * x + y * y
      Sxx += x * x; Sxy += x * y; Syy += y * y
      Sxz += x * z; Syz += y * z
      Sx += x; Sy += y; Sz += z
    }
    const sol = solve3([[Sxx, Sxy, Sx], [Sxy, Syy, Sy], [Sx, Sy, n]], [-Sxz, -Syz, -Sz])
    if (!sol) return null
    const [D, E, F] = sol
    const cx = -D / 2, cy = -E / 2
    const rr = cx * cx + cy * cy - F
    if (!(rr > 0)) return null
    const r = Math.sqrt(rr)
    if (!isFinite(r) || r > 500) return null
    // qualidade do ajuste + cobertura angular
    let sse = 0
    const angs = []
    for (const p of pts) {
      const x = p.x - cx0 - cx, y = p.y - cy0 - cy
      sse += (Math.hypot(x, y) - r) ** 2
      angs.push(Math.atan2(y, x) * R2D)
    }
    return { x: cx + cx0, y: cy + cy0, r, rms: Math.sqrt(sse / n), span: angularSpan(angs) }
  }

  /** maior cobertura angular contígua de uma lista de ângulos (graus) */
  function angularSpan(angs) {
    if (angs.length < 2) return 0
    const s = angs.map(a => (a + 360) % 360).sort((a, b) => a - b)
    let maxGap = (s[0] + 360) - s[s.length - 1]
    for (let i = 1; i < s.length; i++) maxGap = Math.max(maxGap, s[i] - s[i - 1])
    return 360 - maxGap
  }

  // ------------------------------------------------------------ raio de giro

  /**
   * Raio de giro esperado. É a soma do alcance horizontal da amarra com o
   * comprimento do barco (o GPS fica a bordo, não na âncora) e uma margem de GPS.
   *
   *   horizontal = sqrt(amarra² - (profundidade + altura da roleta)²)
   *
   * Essa é a hipótese de amarra retesada (pior caso, vento forte). Com pouco
   * vento a amarra faz catenária e o barco fica mais perto — por isso o raio
   * calculado é o LIMITE, não a posição típica.
   */
  function swingRadius(cfg) {
    const vertical = (cfg.depth || 0) + (cfg.bowRoller || 1.2)
    const rode = cfg.rodeLength || 0
    const horizontal = rode > vertical ? Math.sqrt(rode * rode - vertical * vertical) : 0
    return horizontal + (cfg.boatLength || 0) + (cfg.gpsMargin != null ? cfg.gpsMargin : 5)
  }

  /** relação de fundeio (scope) = amarra / (profundidade + roleta) */
  function scopeRatio(cfg) {
    const vertical = (cfg.depth || 0) + (cfg.bowRoller || 1.2)
    return vertical > 0 ? (cfg.rodeLength || 0) / vertical : 0
  }

  // ------------------------------------------------------------- configuração

  const DEFAULTS = {
    // --- barco / fundeio -----------------------------------------------
    boatLength: 8,        // m — comprimento do barco (a antena gira em torno da proa)
    antennaToBow: 4,      // m — distância da antena do SAFEBOAT até a roleta da proa
    rodeLength: 40,       // m — amarra/cabo lançado
    depth: 6,             // m — profundidade sob a quilha no fundeio
    bowRoller: 1.2,       // m — altura da roleta acima da água
    gpsMargin: 5,         // m — folga para erro de GPS
    alarmRadius: null,    // m — se null, usa swingRadius(); se número, manda o usuário

    // --- detecção -------------------------------------------------------
    confirmSeconds: 45,   // s fora do raio (contínuos) para confirmar garrando
    prealarmFraction: 0.85, // fração do raio que acende a atenção
    driftWindowMin: 20,   // min — janela do detector de deriva lenta do centro
    driftThreshold: 0.15, // fração do raio: quanto o CENTRO pode migrar antes de alarmar
    maxFixAgeSec: 30,     // s sem posição válida = alarme de perda de sinal
    accuracyLimit: 25,    // m — acima disso a posição é considerada ruim
    speedGate: 4.1,       // m/s (~8 nós) — salto acima disso entre fixes = multipath, descarta
    autoFitAnchor: true,  // refina a posição da âncora ajustando círculo ao arco de giro
    holdOffSeconds: 90,   // s após armar antes de poder alarmar (deixa o barco assentar)
  }

  // -------------------------------------------------------------- estados

  const STATE = {
    IDLE: 'idle',         // âncora não lançada / alarme desligado
    SETTING: 'setting',   // âncora lançada, verificando aguante (dando ré)
    ARMED: 'armed',       // vigiando, tudo normal
    PREALARM: 'prealarm', // encostando no limite ou centro migrando
    ALARM: 'alarm',       // garrando confirmado
    NOSIGNAL: 'nosignal', // sem posição válida
  }

  // ------------------------------------------------------- filtro de posição

  /**
   * Filtro de posição adaptativo. Não é Kalman completo de propósito: precisa
   * rodar em microcontrolador. Peso do fix novo cai quando a precisão relatada
   * pelo GPS piora, e saltos fisicamente impossíveis (multipath, típico em
   * marina com cais alto ou sob ponte) são descartados.
   */
  class PositionFilter {
    constructor(cfg) {
      this.cfg = cfg
      this.est = null      // {x,y} local
      this.lastT = null
      this.rejected = 0
    }
    reset() { this.est = null; this.lastT = null; this.rejected = 0 }
    push(local, t, accuracy) {
      const acc = accuracy != null ? accuracy : 8
      if (!this.est) { this.est = { x: local.x, y: local.y }; this.lastT = t; return this.est }
      const dt = Math.max(0.2, (t - this.lastT) / 1000)
      const jump = Math.hypot(local.x - this.est.x, local.y - this.est.y)
      // porta de velocidade: barco fundeado não anda a 8 nós
      if (jump / dt > this.cfg.speedGate && this.rejected < 5) { this.rejected++; return this.est }
      this.rejected = 0
      // alpha ~ 0.45 com GPS bom (3 m), ~0.12 com GPS ruim (20 m)
      const alpha = Math.max(0.08, Math.min(0.5, 1.6 / (acc + 1.5)))
      this.est = { x: this.est.x + alpha * (local.x - this.est.x), y: this.est.y + alpha * (local.y - this.est.y) }
      this.lastT = t
      return this.est
    }
  }

  // ------------------------------------------------------------ vigia âncora

  /**
   * AnchorWatch — máquina de estados da vigília de âncora.
   *
   * Uso:
   *   const w = new AnchorWatch({ boatLength: 8, rodeLength: 40, depth: 6 })
   *   w.dropAnchor(fix)            // marca o ponto de lançamento
   *   w.arm()                      // começa a vigiar
   *   w.feed({t, lat, lon, accuracy, sog, cog, heading})   // 1 Hz
   *   w.snapshot()                 // estado para a UI / telemetria
   */
  class AnchorWatch {
    constructor(config) {
      this.cfg = Object.assign({}, DEFAULTS, config || {})
      this.reset()
    }

    reset() {
      this.state = STATE.IDLE
      this.anchor = null        // {lat,lon} ponto da âncora (estimado ou marcado)
      this.anchorOrigin = null  // marcação original, base da trava cumulativa do refino
      this.anchorSource = null  // 'marcado' | 'ajuste-arco' | 'manual' | 'retroativo'
      this.ref = null           // origem do plano local
      this.filter = new PositionFilter(this.cfg)
      this.track = []           // rastro filtrado: {t,x,y,r,brg,acc,raw}
      this.events = []          // histórico de eventos para a UI
      this.armedAt = null
      this.outsideSince = null
      this.insideSince = null
      this.lastFix = null
      this.maxRadiusSeen = 0
      this.driftRef = null      // referência do início da deriva do centro
      this.driftLostAt = null
      this._noDrift()
      this.fitted = null        // último ajuste de círculo
      this.stats = { fixes: 0, rejected: 0 }
    }

    // ---- configuração ------------------------------------------------------

    setConfig(patch) {
      Object.assign(this.cfg, patch)
      this.filter.cfg = this.cfg
      return this.cfg
    }

    /** raio de alarme em uso (manual se definido, senão calculado) */
    get radius() {
      return this.cfg.alarmRadius != null ? this.cfg.alarmRadius : swingRadius(this.cfg)
    }

    // ---- ciclo de vida -----------------------------------------------------

    /**
     * Marca o ponto onde a âncora tocou o fundo. Chamado quando o usuário
     * aperta "lancei a âncora" — a bordo, o ideal é o momento exato do
     * lançamento, e a posição usada é a da PROA, não a da antena.
     */
    dropAnchor(fix) {
      const bow = this._bowPosition(fix)
      this.anchor = bow
      this.anchorOrigin = { lat: bow.lat, lon: bow.lon }
      this.anchorSource = 'marcado'
      this.ref = { lat: bow.lat, lon: bow.lon }
      this.filter.reset()
      this.track = []
      this.maxRadiusSeen = 0
      this.state = STATE.SETTING
      this._event('ancora', 'Âncora lançada — verificando aguante')
      return this.anchor
    }

    /**
     * Define a âncora manualmente (usuário arrastou o pino no mapa, ou informou
     * rumo+distância a partir da posição atual).
     */
    setAnchor(pos, source) {
      this.anchor = { lat: pos.lat, lon: pos.lon }
      if (source !== 'ajuste-arco') this.anchorOrigin = { lat: pos.lat, lon: pos.lon }
      this.anchorSource = source || 'manual'
      this.ref = { lat: pos.lat, lon: pos.lon }
      this.filter.reset()
      this.maxRadiusSeen = 0
      this._event('ancora', 'Posição da âncora ajustada')
      return this.anchor
    }

    /**
     * Fundeou sem marcar nada e só depois lembrou do alarme? Estima a âncora
     * a partir do rastro já gravado pelo dispositivo (que, sendo fixo a bordo,
     * está gravando desde antes). Ajusta um círculo ao arco de giro.
     * Este é o caso de uso que os apps de celular não conseguem cobrir.
     */
    anchorFromTrack(trackFixes) {
      if (!trackFixes || trackFixes.length < 12) return null
      const ref = { lat: trackFixes[0].lat, lon: trackFixes[0].lon }
      const pts = trackFixes.map(f => toLocal(ref, f))
      const fit = fitCircle(pts)
      if (!fit) return null
      const pos = fromLocal(ref, fit)
      // arco curto: o centro do círculo é chute. Usa o centróide como âncora e
      // avisa a UI que a confiança é baixa.
      if (fit.span < 70) {
        const cx = pts.reduce((s, p) => s + p.x, 0) / pts.length
        const cy = pts.reduce((s, p) => s + p.y, 0) / pts.length
        this.setAnchor(fromLocal(ref, { x: cx, y: cy }), 'retroativo')
        this.fitted = { span: fit.span, r: fit.r, rms: fit.rms, confident: false }
        return { pos: this.anchor, confident: false, span: fit.span, radius: fit.r }
      }
      this.setAnchor(pos, 'ajuste-arco')
      this.fitted = { span: fit.span, r: fit.r, rms: fit.rms, confident: true }
      return { pos, confident: true, span: fit.span, radius: fit.r }
    }

    /** liga a vigília */
    arm() {
      if (!this.anchor) return false
      this.state = STATE.ARMED
      this.armedAt = this.lastFix ? this.lastFix.t : Date.now()
      this.outsideSince = null
      this._event('armado', `Alarme ativo — raio ${Math.round(this.radius)} m`)
      return true
    }

    /** desliga a vigília (âncora continua marcada) */
    disarm() {
      this.state = STATE.IDLE
      this.outsideSince = null
      this._event('desarmado', 'Alarme desativado')
    }

    /** silencia o alarme mas continua vigiando a partir da posição atual */
    acknowledge() {
      if (this.state === STATE.ALARM || this.state === STATE.PREALARM) {
        this.state = STATE.ARMED
        this.outsideSince = null
        this._event('reconhecido', 'Alarme reconhecido pelo tripulante')
      }
    }

    // ---- alimentação -------------------------------------------------------

    /**
     * Consome um fix. `fix`: {t (ms), lat, lon, accuracy (m), sog (m/s),
     * cog (°), heading (°), depth (m)}
     */
    feed(fix) {
      this.stats.fixes++
      this.lastFix = fix
      if (fix.depth != null && this.state === STATE.SETTING) this.cfg.depth = fix.depth

      if (!this.anchor) return this.snapshot()
      if (!this.ref) this.ref = { lat: this.anchor.lat, lon: this.anchor.lon }

      // posição da PROA (onde a amarra sai), não da antena
      const bow = this._bowPosition(fix)
      const local = toLocal(this.ref, bow)
      const before = this.filter.est
      const est = this.filter.push(local, fix.t, fix.accuracy)
      if (before && est === before) this.stats.rejected++

      const anchorLocal = toLocal(this.ref, this.anchor)
      const dx = est.x - anchorLocal.x, dy = est.y - anchorLocal.y
      const r = Math.hypot(dx, dy)
      const brg = (Math.atan2(dx, dy) * R2D + 360) % 360

      this.track.push({ t: fix.t, x: est.x, y: est.y, r, brg, acc: fix.accuracy, raw: local })
      // ~6 h de rastro a 1 Hz seria muito para o navegador; guarda 4000 pontos
      if (this.track.length > 4000) this.track.splice(0, this.track.length - 4000)
      if (this.state !== STATE.SETTING) this.maxRadiusSeen = Math.max(this.maxRadiusSeen, r)

      this._updateDrift()
      if (this.cfg.autoFitAnchor) this._maybeRefineAnchor()
      this._evaluate(fix, r)
      return this.snapshot()
    }

    // ---- interno -----------------------------------------------------------

    /** posição da roleta de proa a partir da antena + proa do barco */
    _bowPosition(fix) {
      const hdg = fix.heading != null ? fix.heading : fix.cog
      if (hdg == null || !this.cfg.antennaToBow) return { lat: fix.lat, lon: fix.lon }
      return destination(fix, this.cfg.antennaToBow, hdg)
    }

    _event(kind, text) {
      const t = this.lastFix ? this.lastFix.t : Date.now()
      this.events.push({ t, kind, text })
      if (this.events.length > 200) this.events.shift()
    }

    /**
     * Detector de deriva lenta do CENTRO de giro — o coração da coisa.
     *
     * O que separa vento rondando de âncora garrando:
     *   - RONDA DE VENTO: o barco vai para o outro lado do círculo. A distância
     *     até a âncora oscila mas NÃO cresce de forma sustentada.
     *   - GARRANDO DEVAGAR: o barco pode nem sair do círculo por meia hora, mas
     *     a nuvem de posições escorrega sempre para o mesmo lado e a distância
     *     até a âncora marcada cresce sem parar.
     * Um alarme só por raio deixa passar o segundo caso por tempo demais — e é
     * o segundo caso que arrasta barco para cima da pedra.
     *
     * Problema estatístico: garrando a 0,4 m/min o sinal é ~8 m em 20 min,
     * enquanto a guinada normal do barco tem amplitude de ±20 m. Comparar médias
     * de duas metades de janela não resolve, porque a guinada é AUTOCORRELACIONADA
     * (período de 60-150 s) — a média de uma metade continua ruidosa.
     *
     * Solução: média em blocos de 2 min (mata a autocorrelação da guinada) e
     * regressão linear sobre as médias de bloco, com teste de significância. Só
     * conta como deriva o que tem velocidade estatisticamente significativa E
     * distância à âncora crescendo junto — a segunda condição é o que derruba os
     * falsos positivos de inversão de maré e ronda de vento, onde o barco
     * atravessa o círculo mas não se afasta de forma sustentada.
     */
    _updateDrift() {
      const win = this.cfg.driftWindowMin * 60000
      const now = this.track[this.track.length - 1].t
      const recent = []
      for (let i = this.track.length - 1; i >= 0; i--) {
        if (now - this.track[i].t > win) break
        recent.push(this.track[i])
      }
      recent.reverse()
      if (recent.length < 90) return this._noDrift()

      // --- médias em blocos de 2 min ---------------------------------------
      const BLOCK = 120000
      const t0 = recent[0].t
      const acc = []
      for (const p of recent) {
        const k = Math.floor((p.t - t0) / BLOCK)
        if (!acc[k]) acc[k] = { n: 0, x: 0, y: 0, r: 0, t: 0 }
        const b = acc[k]
        b.n++; b.x += p.x; b.y += p.y; b.r += p.r; b.t += p.t
      }
      const B = acc.filter(b => b && b.n >= 40).map(b => ({ x: b.x / b.n, y: b.y / b.n, r: b.r / b.n, t: b.t / b.n }))
      if (B.length < 5) return this._noDrift()

      // --- regressão linear com erro padrão da inclinação -------------------
      const reg = (key) => {
        const n = B.length, base = B[0].t
        let st = 0, sv = 0, stt = 0, stv = 0
        for (const b of B) { const tt = (b.t - base) / 60000; st += tt; sv += b[key]; stt += tt * tt; stv += tt * b[key] }
        const den = n * stt - st * st
        if (Math.abs(den) < 1e-9) return { slope: 0, se: Infinity }
        const slope = (n * stv - st * sv) / den
        const icpt = (sv - slope * st) / n
        let sse = 0
        for (const b of B) { const tt = (b.t - base) / 60000; sse += (b[key] - (icpt + slope * tt)) ** 2 }
        const se = Math.sqrt((sse / Math.max(1, n - 2)) * n / den)
        return { slope, se }
      }
      const rx = reg('x'), ry = reg('y'), rr = reg('r')

      const rate = Math.hypot(rx.slope, ry.slope)           // m/min do centro de giro
      const seV = Math.hypot(rx.se, ry.se) || 1e-9
      const tVel = rate / seV                                // significância da velocidade
      const tRad = rr.se > 0 && isFinite(rr.se) ? rr.slope / rr.se : 0  // significância do afastamento
      const brg = (Math.atan2(rx.slope, ry.slope) * R2D + 360) % 360

      // --- RADIAL vs TANGENCIAL: o teste que derruba o falso alarme de ronda --
      // Barco girando em torno da âncora (ronda de vento, inversão de maré,
      // volta na poita) move-se TANGENCIALMENTE: a velocidade é perpendicular à
      // linha âncora→barco. Âncora garrando empurra o barco RADIALMENTE, para
      // longe do ponto marcado. Sem esse teste, uma ronda de 180° parece uma
      // deriva enorme e constante — e é exatamente a queixa nº 1 dos usuários
      // dos apps de celular ("acordei 3h da manhã e o barco estava no lugar").
      // Compara com a direção radial MÉDIA da janela, não com a instantânea: num
      // giro, a corda do arco é perpendicular ao raio médio (align ≈ 0) qualquer
      // que seja o tamanho do arco. Contra o raio instantâneo, um arco largo
      // começa a parecer radial e o falso alarme volta.
      const anchorLocal = toLocal(this.ref, this.anchor)
      const cen = centroid(recent)
      const meanBrg = (Math.atan2(cen.x - anchorLocal.x, cen.y - anchorLocal.y) * R2D + 360) % 360
      const radialAlign = Math.cos(angleDiff(brg, meanBrg) * D2R) // 1 = afastando, 0 = girando

      // deriva significativa: anda de verdade, se afasta da âncora marcada, e o
      // movimento é radial (não é o barco dando a volta no círculo)
      const significant = tVel > 2.0 && tRad > 1.0 && rate > 0.08 && radialAlign > 0.6

      // --- acumulado desde o início da deriva -------------------------------
      // Regressão dá velocidade; o alarme precisa de DESLOCAMENTO. Fixa uma
      // referência quando a deriva começa e mede o quanto o centro já andou.
      const head = B[0], tail = B[B.length - 1]
      if (significant) {
        if (!this.driftRef) this.driftRef = { x: head.x, y: head.y, t: head.t }
        this.driftLostAt = null
      } else if (this.driftRef) {
        // tolera perda momentânea de significância (rajada bagunça a regressão)
        if (!this.driftLostAt) this.driftLostAt = now
        else if (now - this.driftLostAt > 6 * 60000) { this.driftRef = null; this.driftLostAt = null }
      }
      const accumulated = this.driftRef ? Math.hypot(tail.x - this.driftRef.x, tail.y - this.driftRef.y) : 0

      this.drift = {
        rate, brg, tVel, tRad, significant, accumulated, radialAlign,
        sinceMin: this.driftRef ? (now - this.driftRef.t) / 60000 : 0,
        radiusRate: rr.slope,
        // compatibilidade com a UI: `dist` = deslocamento acumulado do centro
        dist: accumulated,
        confident: significant,
      }
    }

    _noDrift() {
      this.drift = { rate: 0, brg: 0, tVel: 0, tRad: 0, significant: false, accumulated: 0, sinceMin: 0, radiusRate: 0, radialAlign: 0, dist: 0, confident: false }
    }

    /**
     * Refina a posição da âncora ajustando um círculo ao arco de giro.
     *
     * PERIGO destа função: se ela seguir o barco, o alarme nunca toca — a âncora
     * "virtual" anda junto com a âncora que está garrando e tudo parece normal.
     * Num veleiro, que guina muito mais, o arco fica largo o bastante para o
     * ajuste parecer confiável e o efeito é brutal: em teste, a detecção pulou de
     * 16 m para 163 m de garrada. Limitar o passo não basta, porque ele se repete
     * e vai andando aos poucos. Por isso as travas abaixo são CUMULATIVAS e o
     * refino é desligado à menor suspeita de deriva.
     */
    _maybeRefineAnchor() {
      if (this.state !== STATE.ARMED) return
      if (this.drift.significant) return                       // suspeita de deriva: não mexe
      if (this.track.length < 120 || this.track.length % 60 !== 0) return

      const recent = this.track.slice(-900)
      const fit = fitCircle(recent)
      if (!fit) return
      const expected = this.radius
      this.fitted = {
        span: fit.span, r: fit.r, rms: fit.rms,
        confident: fit.span >= 90 && fit.rms < 6 && fit.r < expected * 1.3,
      }
      if (!this.fitted.confident) return

      const anchorLocal = toLocal(this.ref, this.anchor)
      const move = Math.hypot(fit.x - anchorLocal.x, fit.y - anchorLocal.y)
      if (move > expected * 0.2) return                        // passo grande = suspeito

      // trava cumulativa: some tudo o que já foi corrigido desde a marcação
      // original. O refino serve para acertar o erro de quem apertou o botão
      // alguns segundos depois de largar a âncora — nunca para acompanhar o barco.
      const originLocal = toLocal(this.ref, this.anchorOrigin || this.anchor)
      const total = Math.hypot(fit.x - originLocal.x, fit.y - originLocal.y)
      if (total > expected * 0.25) return

      this.anchor = fromLocal(this.ref, fit)
      this.anchorSource = 'ajuste-arco'
    }

    /** máquina de estados do alarme */
    _evaluate(fix, r) {
      if (this.state === STATE.IDLE) return

      // --- perda de sinal --------------------------------------------------
      const bad = fix.accuracy != null && fix.accuracy > this.cfg.accuracyLimit
      if (fix.novalid || bad) {
        if (this.state === STATE.ARMED || this.state === STATE.PREALARM) {
          this.state = STATE.NOSIGNAL
          this._event('sinal', 'Sinal de GPS degradado — vigília em dúvida')
        }
        return
      }
      if (this.state === STATE.NOSIGNAL) {
        this.state = STATE.ARMED
        this._event('sinal', 'Sinal de GPS restabelecido')
      }

      if (this.state === STATE.SETTING) {
        // durante a verificação de aguante o barco recua contra o motor; sair do
        // raio aqui é esperado, não é alarme.
        return
      }
      if (this.state !== STATE.ARMED && this.state !== STATE.PREALARM && this.state !== STATE.ALARM) return

      // carência após armar: deixa o barco assentar antes de poder alarmar
      if (this.armedAt && fix.t - this.armedAt < this.cfg.holdOffSeconds * 1000) return

      const R = this.radius
      const outside = r > R
      // margem de GPS entra também no limite instantâneo: precisão ruim = limite
      // mais generoso, para não acordar ninguém por causa de multipath.
      const hardLimit = R + Math.max(0, (fix.accuracy || 5) - 5) * 0.8

      if (r > hardLimit) {
        if (!this.outsideSince) this.outsideSince = fix.t
      } else if (r < R * 0.92) {
        this.outsideSince = null
      }

      const sustained = this.outsideSince && (fix.t - this.outsideSince) >= this.cfg.confirmSeconds * 1000
      // deriva confirmada: o centro de giro já andou o suficiente para não ser
      // ruído nem guinada. Em raio de 52 m dá ~8 m de migração do centro.
      const creepLimit = Math.max(6, R * this.cfg.driftThreshold)
      const creepFar = this.drift.significant && this.drift.accumulated > creepLimit

      // --- limite do que a AMARRA consegue explicar --------------------------
      // Com vento subindo, a amarra vai de catenária a retesada e o barco se
      // afasta radialmente — mesma assinatura de garrar devagar. A diferença é
      // que esticar a amarra SATURA: acaba no comprimento lançado. Garrar não
      // tem limite. Então deriva radial só vira ALARME depois que o barco passa
      // do que a amarra consegue explicar; antes disso é só atenção.
      // (Com anemômetro a bordo dá para separar antes — ver README, "vento".)
      const rodeLimit = swingRadius(Object.assign({}, this.cfg, { boatLength: 0, gpsMargin: 0 }))
      const explainable = rodeLimit > 0 ? rodeLimit + (this.cfg.gpsMargin != null ? this.cfg.gpsMargin : 5) : R * 0.85
      const creeping = creepFar && r > explainable

      if (sustained || creeping) {
        if (this.state !== STATE.ALARM) {
          this.state = STATE.ALARM
          const motivo = sustained
            ? `fora do raio há ${Math.round((fix.t - this.outsideSince) / 1000)}s`
            : `centro de giro migrou ${this.drift.accumulated.toFixed(0)} m a ${this.drift.rate.toFixed(2)} m/min`
          this._event('alarme', `GARRANDO — ${motivo}`)
        }
        return
      }

      const nearLimit = r > R * this.cfg.prealarmFraction
      // atenção já na PRIMEIRA suspeita de deriva, bem antes do alarme: dá ao
      // tripulante a chance de olhar antes de ser acordado por sirene.
      const creepSuspect = creepFar || (this.drift.significant && this.drift.accumulated > creepLimit * 0.45)
      if (nearLimit || creepSuspect) {
        if (this.state === STATE.ARMED) {
          this.state = STATE.PREALARM
          this._event('atencao', creepSuspect
            ? `Centro de giro migrando ${this.drift.rate.toFixed(2)} m/min`
            : 'Encostando no limite do raio')
        }
        return
      }
      if (this.state === STATE.PREALARM) {
        this.state = STATE.ARMED
        this._event('normal', 'Voltou para dentro do raio')
      }
    }

    // ---- saída -------------------------------------------------------------

    /** estado completo para a UI / telemetria / push */
    snapshot() {
      const last = this.track[this.track.length - 1]
      const R = this.radius
      return {
        state: this.state,
        anchor: this.anchor,
        anchorSource: this.anchorSource,
        radius: R,
        scope: scopeRatio(this.cfg),
        position: last ? fromLocal(this.ref, last) : (this.lastFix ? { lat: this.lastFix.lat, lon: this.lastFix.lon } : null),
        distance: last ? last.r : 0,
        bearing: last ? last.brg : 0,
        usage: last ? Math.min(1.5, last.r / R) : 0,
        maxRadiusSeen: this.maxRadiusSeen,
        drift: this.drift,
        fitted: this.fitted,
        outsideFor: this.outsideSince && last ? Math.round((last.t - this.outsideSince) / 1000) : 0,
        accuracy: this.lastFix ? this.lastFix.accuracy : null,
        heading: this.lastFix ? this.lastFix.heading : null,
        sog: this.lastFix ? this.lastFix.sog : null,
        depth: this.cfg.depth,
        t: last ? last.t : null,
        stats: this.stats,
      }
    }

    /** rastro em lat/lon para desenhar no mapa */
    trackLatLon(maxPoints) {
      const step = Math.max(1, Math.ceil(this.track.length / (maxPoints || 600)))
      const out = []
      for (let i = 0; i < this.track.length; i += step) out.push(Object.assign(fromLocal(this.ref, this.track[i]), { t: this.track[i].t, r: this.track[i].r }))
      return out
    }
  }

  function centroid(pts) {
    let x = 0, y = 0
    for (const p of pts) { x += p.x; y += p.y }
    return { x: x / pts.length, y: y / pts.length }
  }

  return {
    AnchorWatch, PositionFilter, STATE, DEFAULTS,
    toLocal, fromLocal, distance, bearing, destination, angleDiff,
    fitCircle, angularSpan, swingRadius, scopeRatio, metersPerDegree, centroid,
  }
})

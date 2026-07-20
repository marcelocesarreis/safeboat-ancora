/* SAFEBOAT — Dispositivo simulado (barco fundeado)
 * =================================================
 * Gera fixes de GPS realistas de um barco fundeado ou preso numa poita, com os
 * fenômenos que fazem os alarmes de âncora de celular tocarem à toa de
 * madrugada — que é justamente o que precisamos NÃO reproduzir:
 *
 *   - o barco "veleja" no fundeio (guinadas de ±20..35° em torno da amarra);
 *   - rajada retesa a amarra e joga o barco para o limite do raio;
 *   - ronda de vento leva o barco para o lado oposto do círculo;
 *   - inversão de maré gira o barco e muda a profundidade (logo, o scope);
 *   - multipath perto de cais/costão dá saltos de 15-30 m na posição;
 *   - e, no meio disso tudo, a âncora garrando devagar (0,2-0,5 m/min), que é o
 *     caso que de fato importa e o mais difícil de separar do resto.
 *
 * A interface de saída é a MESMA que o SAFEBOAT real vai entregar (ver
 * device-adapter.cjs), então trocar simulação por hardware não mexe na UI nem
 * no núcleo de decisão.
 */
(function (root, factory) {
  const api = factory()
  if (typeof module === 'object' && module.exports) module.exports = api
  root.SBSim = api
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict'

  const D2R = Math.PI / 180
  const R2D = 180 / Math.PI

  // gerador pseudoaleatório com semente: a mesma simulação repete igual, o que
  // é essencial para comparar ajustes de parâmetro do detector.
  function mulberry32(seed) {
    let a = seed >>> 0
    return function () {
      a |= 0; a = (a + 0x6D2B79F5) | 0
      let t = Math.imul(a ^ (a >>> 15), 1 | a)
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
  }

  /** ruído gaussiano (Box-Muller) */
  function gauss(rnd) {
    let u = 0, v = 0
    while (u === 0) u = rnd()
    while (v === 0) v = rnd()
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v)
  }

  // -------------------------------------------------------------- cenários

  /**
   * Cada cenário é uma função do tempo (minutos desde o início) que devolve as
   * forçantes do ambiente. `dragRate` em m/min é o quanto a ÂNCORA anda no fundo.
   */
  const SCENARIOS = {
    calma: {
      nome: 'Noite calma',
      desc: 'Vento fraco e constante, 8-12 nós. O caso normal: não pode tocar alarme nenhum.',
      esperado: 'sem alarme',
      env: () => ({ windDir: 135, windSpd: 5, gust: 1.5, currentDir: 0, currentSpd: 0, dragRate: 0, tide: 0 }),
    },

    rajadas: {
      nome: 'Frente com rajadas',
      desc: 'Vento sobe de 12 para 35 nós em rajadas. O barco retesa a amarra e chega no limite do raio — armadilha clássica de falso alarme.',
      esperado: 'atenção sim, alarme não',
      env: (min) => {
        const ramp = Math.min(1, min / 25)
        return { windDir: 150 + 8 * Math.sin(min / 6), windSpd: 6 + 12 * ramp, gust: 2 + 8 * ramp, currentDir: 0, currentSpd: 0, dragRate: 0, tide: 0 }
      },
    },

    'ronda-vento': {
      nome: 'Ronda de vento 180°',
      desc: 'Vento roda de S para N ao longo de 40 min. O barco atravessa o círculo inteiro e vai parar do lado oposto — distância da âncora quase não muda, mas o rumo inverte.',
      esperado: 'sem alarme',
      env: (min) => ({ windDir: 180 + 180 * clamp01((min - 20) / 40), windSpd: 7, gust: 2.5, currentDir: 0, currentSpd: 0, dragRate: 0, tide: 0 }),
    },

    mare: {
      nome: 'Inversão de maré',
      desc: 'Corrente inverte 180° e a profundidade varia 1,8 m. Barco gira em torno da âncora e o scope efetivo muda com a maré.',
      esperado: 'sem alarme',
      env: (min) => {
        const phase = (min / 60) * Math.PI  // meia oscilação por hora simulada
        return {
          windDir: 90, windSpd: 3.5, gust: 1.2,
          currentDir: min < 45 ? 70 : 250, currentSpd: 0.55 * Math.abs(Math.cos(phase)),
          dragRate: 0, tide: 0.9 * Math.sin(phase),
        }
      },
    },

    multipath: {
      nome: 'Multipath perto do cais',
      desc: 'Fundeado junto a um costão/cais alto: o GPS dá saltos de 15-30 m e a precisão relatada piora. Ninguém pode ser acordado por isso.',
      esperado: 'sem alarme',
      env: () => ({ windDir: 120, windSpd: 5, gust: 2, currentDir: 0, currentSpd: 0, dragRate: 0, tide: 0, multipath: true }),
    },

    garrando: {
      nome: 'Garrando de verdade',
      desc: 'Vento forte e a âncora não pegou: sai andando a 2,5 m/min para sotavento. É o alarme que tem que tocar, e rápido.',
      esperado: 'ALARME',
      env: (min) => ({ windDir: 160, windSpd: 13, gust: 5, currentDir: 0, currentSpd: 0, dragRate: min > 12 ? 2.5 : 0, tide: 0 }),
    },

    'garrando-lento': {
      nome: 'Garrando devagar',
      desc: 'A âncora escorrega 0,4 m/min. Durante muitos minutos o barco continua DENTRO do raio — só o centro do giro migra. Alarme por raio só percebe tarde demais.',
      esperado: 'ALARME (pelo centro migrando)',
      env: (min) => ({ windDir: 200, windSpd: 9, gust: 3, currentDir: 0, currentSpd: 0, dragRate: min > 10 ? 0.4 : 0, tide: 0 }),
    },

    poita: {
      nome: 'Poita (boia de amarração)',
      desc: 'Preso numa poita com cabo curto. O raio é pequeno e o barco dá volta completa com a maré. Sem scope para calcular — o raio é cabo + comprimento do barco.',
      esperado: 'sem alarme',
      mooring: true,
      env: (min) => ({ windDir: (40 + min * 4) % 360, windSpd: 4.5, gust: 2, currentDir: 0, currentSpd: 0, dragRate: 0, tide: 0 }),
    },

    'poita-rompida': {
      nome: 'Poita rompida / cabo partido',
      desc: 'O cabo da poita parte e o barco sai à deriva com vento e corrente. Aceleração clara, sem volta.',
      esperado: 'ALARME',
      mooring: true,
      env: (min) => ({ windDir: 70, windSpd: 8, gust: 3, currentDir: 60, currentSpd: min > 15 ? 0.6 : 0, dragRate: min > 15 ? 9 : 0, tide: 0 }),
    },

    'perda-sinal': {
      nome: 'Perda de sinal de GPS',
      desc: 'Antena obstruída: a precisão degrada e depois some. O sistema tem que avisar que está vigiando às cegas, não fingir que está tudo bem.',
      esperado: 'aviso de sinal',
      env: (min) => ({ windDir: 130, windSpd: 6, gust: 2, currentDir: 0, currentSpd: 0, dragRate: 0, tide: 0, gpsFail: min > 18 && min < 34 }),
    },
  }

  function clamp01(v) { return Math.max(0, Math.min(1, v)) }

  // -------------------------------------------------------- barco simulado

  /**
   * SimulatedBoat — física simplificada de um barco no fundeio.
   *
   * Modelo: a proa fica a sotavento da âncora, a uma distância que depende da
   * pressão do vento sobre a amarra (rajada estica, calmaria encolhe pela
   * catenária). Em cima disso entra a guinada — o barco veleja em torno da
   * amarra com período de 60-150 s, que é o que mais atrapalha os detectores
   * ingênuos.
   */
  class SimulatedBoat {
    constructor(opts) {
      const o = opts || {}
      this.origin = o.origin || { lat: -27.5954, lon: -48.5480 } // Florianópolis
      this.cfg = {
        boatLength: o.boatLength != null ? o.boatLength : 8,
        antennaToBow: o.antennaToBow != null ? o.antennaToBow : 4,
        rodeLength: o.rodeLength != null ? o.rodeLength : 40,
        depth: o.depth != null ? o.depth : 6,
        bowRoller: 1.2,
        windage: o.windage != null ? o.windage : 1, // 1 = lancha; 1.4 = veleiro (veleja mais)
      }
      this.scenario = o.scenario || 'calma'
      this.rnd = mulberry32(o.seed != null ? o.seed : 1234)
      this.t0 = o.t0 != null ? o.t0 : Date.now()
      this.reset()
    }

    reset() {
      this.tMin = 0
      this.anchor = { x: 0, y: 0 }       // âncora no plano local (m) — pode migrar se garrar
      this.pos = { x: 0, y: 0 }          // proa do barco
      this.yawPhase = this.rnd() * Math.PI * 2
      this.radiusState = 0
      this.heading = 0
      this.baseDepth = this.cfg.depth
      this.settled = false
      this.log = []
    }

    /** raio horizontal máximo da amarra (amarra retesada) */
    maxRadius(depth) {
      const sc = SCENARIOS[this.scenario]
      if (sc && sc.mooring) return this.cfg.rodeLength + this.cfg.boatLength * 0.15
      const vertical = (depth != null ? depth : this.cfg.depth) + this.cfg.bowRoller
      const L = this.cfg.rodeLength
      return L > vertical ? Math.sqrt(L * L - vertical * vertical) : 0
    }

    /** avança a simulação em `dt` segundos e devolve um fix */
    step(dt) {
      this.tMin += dt / 60
      const sc = SCENARIOS[this.scenario] || SCENARIOS.calma
      const env = sc.env(this.tMin)
      const depth = this.baseDepth + (env.tide || 0)

      // ---- forçante resultante (vento + corrente) -------------------------
      const gust = env.windSpd + (env.gust || 0) * Math.max(0, gauss(this.rnd)) * (0.6 + 0.4 * Math.sin(this.tMin * 1.7))
      const wx = Math.sin(env.windDir * D2R) * gust
      const wy = Math.cos(env.windDir * D2R) * gust
      const cx = Math.sin((env.currentDir || 0) * D2R) * (env.currentSpd || 0) * 6 // corrente pesa mais que vento por m/s
      const cy = Math.cos((env.currentDir || 0) * D2R) * (env.currentSpd || 0) * 6
      const fx = wx + cx, fy = wy + cy
      const force = Math.hypot(fx, fy)
      const forceDir = (Math.atan2(fx, fy) * R2D + 360) % 360

      // ---- âncora garrando ------------------------------------------------
      if (env.dragRate) {
        const d = (env.dragRate * dt) / 60
        this.anchor.x += Math.sin(forceDir * D2R) * d
        this.anchor.y += Math.cos(forceDir * D2R) * d
      }

      // ---- distância da âncora --------------------------------------------
      // amarra retesa com o quadrado do vento e satura no comprimento útil.
      const rMax = this.maxRadius(depth)
      const tension = clamp01((force / 12) ** 1.4)
      const rTarget = rMax * (0.42 + 0.58 * tension)
      // inércia: o barco leva ~40 s para responder
      this.radiusState += (rTarget - this.radiusState) * Math.min(1, dt / 40)

      // ---- guinada (o barco "veleja" no fundeio) ---------------------------
      this.yawPhase += (dt / (75 + 40 * this.rnd())) * Math.PI
      const yawAmp = (sc.mooring ? 12 : 22) * this.cfg.windage * (0.5 + 0.5 * clamp01(force / 10))
      const yaw = yawAmp * Math.sin(this.yawPhase) + 3 * gauss(this.rnd)

      // ---- posição da proa -------------------------------------------------
      const brg = forceDir + yaw
      const target = {
        x: this.anchor.x + Math.sin(brg * D2R) * this.radiusState,
        y: this.anchor.y + Math.cos(brg * D2R) * this.radiusState,
      }
      // suaviza para não teletransportar em ronda de vento (o barco atravessa o
      // círculo, não pula para o outro lado)
      const k = Math.min(1, dt / 22)
      this.pos.x += (target.x - this.pos.x) * k
      this.pos.y += (target.y - this.pos.y) * k

      // proa aponta para a âncora
      const toAnchor = Math.atan2(this.anchor.x - this.pos.x, this.anchor.y - this.pos.y) * R2D
      this.heading = (toAnchor + 360) % 360

      // ---- antena do SAFEBOAT (fica atrás da proa) -------------------------
      const antX = this.pos.x - Math.sin(this.heading * D2R) * this.cfg.antennaToBow
      const antY = this.pos.y - Math.cos(this.heading * D2R) * this.cfg.antennaToBow

      // ---- GPS: ruído, multipath, falha ------------------------------------
      let acc = 3.2 + 1.4 * Math.abs(gauss(this.rnd))
      let nx = gauss(this.rnd) * acc * 0.5, ny = gauss(this.rnd) * acc * 0.5
      if (env.multipath && this.rnd() < 0.035) {
        const spike = 12 + this.rnd() * 20
        const sdir = this.rnd() * 360
        nx += Math.sin(sdir * D2R) * spike
        ny += Math.cos(sdir * D2R) * spike
        acc = 14 + this.rnd() * 12
      }
      const novalid = !!env.gpsFail
      if (env.gpsFail) acc = 40 + this.rnd() * 30

      const m = metersPerDeg(this.origin.lat)
      const fix = {
        t: this.t0 + this.tMin * 60000,
        lat: this.origin.lat + (antY + ny) / m.lat,
        lon: this.origin.lon + (antX + nx) / m.lon,
        accuracy: +acc.toFixed(1),
        heading: +this.heading.toFixed(1),
        cog: +this.heading.toFixed(1),
        sog: +(Math.hypot(target.x - this.pos.x, target.y - this.pos.y) / Math.max(dt, 1)).toFixed(2),
        depth: +depth.toFixed(1),
        novalid,
        // ---- verdade fundamental (só a simulação sabe; a UI usa para conferir)
        truth: {
          anchor: { x: this.anchor.x, y: this.anchor.y },
          boat: { x: this.pos.x, y: this.pos.y },
          dragged: Math.hypot(this.anchor.x, this.anchor.y),
          windDir: env.windDir, windSpd: gust, forceDir,
          rMax, depth,
        },
      }
      return fix
    }

    /** posição lat/lon da âncora verdadeira (para o mapa da simulação) */
    truthAnchorLatLon() {
      const m = metersPerDeg(this.origin.lat)
      return { lat: this.origin.lat + this.anchor.y / m.lat, lon: this.origin.lon + this.anchor.x / m.lon }
    }
  }

  function metersPerDeg(lat) {
    return { lat: 111132.92 - 559.82 * Math.cos(2 * lat * D2R), lon: 111412.84 * Math.cos(lat * D2R) }
  }

  return { SimulatedBoat, SCENARIOS, mulberry32, gauss }
})

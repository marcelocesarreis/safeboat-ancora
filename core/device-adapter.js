/* SAFEBOAT — Adaptador de dispositivo (a costura simulação ↔ hardware real)
 * =========================================================================
 * A UI e o núcleo de decisão consomem SÓ esta interface. Trocar o barco
 * simulado pelo SAFEBOAT de verdade é trocar a implementação aqui — nada mais
 * muda. É o ponto onde o dev do MAIN "pluga" o barco específico.
 *
 * Contrato de um fix (o que todo dispositivo tem que entregar):
 *   {
 *     t: <epoch ms>,
 *     lat, lon: <graus>,
 *     accuracy: <m, raio de erro estimado do GPS>,   // HDOP*URA ou do receptor
 *     heading: <°, proa do barco 0..360 | null>,     // do compasso/AHRS do SAFEBOAT
 *     cog, sog: <° e m/s | null>,                     // rumo e velocidade no fundo
 *     depth: <m sob a quilha | null>,                 // do transdutor, se houver
 *     novalid: <bool>                                 // true se o fix não presta
 *   }
 *
 * Todo adaptador expõe:
 *   start(onFix)  -> começa a emitir fixes (chama onFix a cada posição)
 *   stop()
 *   info()        -> metadados do dispositivo (id do barco, sensores presentes)
 */
(function (root, factory) {
  const api = factory(root)
  if (typeof module === 'object' && module.exports) module.exports = api
  root.SBDevice = api
})(typeof globalThis !== 'undefined' ? globalThis : this, function (root) {
  'use strict'

  const SBSim = (typeof require === 'function') ? require('./sim-device.js') : root.SBSim

  // ------------------------------------------------- adaptador de simulação

  /**
   * SimAdapter — dirige um SimulatedBoat em tempo (real ou acelerado). É o que o
   * protótipo usa. `speed` multiplica o relógio: 60 = 1 min de mar por segundo.
   */
  class SimAdapter {
    constructor(opts) {
      const o = opts || {}
      this.boat = new (SBSim.SimulatedBoat)(o)
      this.speed = o.speed || 60
      this.hz = o.hz || 1
      this.timer = null
      this.onFix = null
      this._scenario = o.scenario || 'calma'
    }
    info() {
      return {
        source: 'simulacao',
        boatId: 'SIM-MAGNA260',
        sensors: { gps: true, heading: true, depth: true, wind: false },
        scenario: this._scenario,
        scenarios: SBSim.SCENARIOS,
      }
    }
    setScenario(name) {
      this._scenario = name
      this.boat.scenario = name
      this.boat.reset()
    }
    setBoatConfig(patch) { Object.assign(this.boat.cfg, patch) }
    /** avança N segundos de mar de uma vez (para "pré-encher" rastro) */
    warmup(seconds) { let f = null; for (let i = 0; i < seconds * this.hz; i++) f = this.boat.step(1 / this.hz); return f }
    start(onFix) {
      this.onFix = onFix
      const period = 1000 / (this.speed * this.hz)
      const tick = () => { this.onFix(this.boat.step(1 / this.hz)) }
      this.timer = setInterval(tick, Math.max(8, period))
    }
    stop() { if (this.timer) { clearInterval(this.timer); this.timer = null } }
  }

  // ----------------------------------------- adaptador do SAFEBOAT real (stub)

  /**
   * SafeboatAdapter — ESQUELETO do dispositivo real. Deixado pronto para o dev
   * do MAIN conectar. O SAFEBOAT roda o núcleo A BORDO e publica telemetria; o
   * app pode tanto receber os fixes crus (e rodar o núcleo localmente para a
   * animação suave) quanto receber o snapshot já decidido pelo barco.
   *
   * Duas fontes possíveis, iguais às câmeras:
   *   - No Wi-Fi do barco: WebSocket direto com o SAFEBOAT (baixa latência).
   *   - Remoto (4G/casa): o relay na nuvem repassa a telemetria do barco.
   *
   * O barco continua VIGIANDO mesmo com o app fechado — o alarme é decidido a
   * bordo e só a NOTIFICAÇÃO (push) viaja. É a diferença essencial para os apps
   * de âncora de celular, que param de vigiar quando o dono desce em terra.
   */
  class SafeboatAdapter {
    constructor(opts) {
      const o = opts || {}
      this.boatId = o.boatId || 'MAGNA260'
      this.wsUrl = o.wsUrl || null          // ws://<safeboat-local>/telemetry  ou  wss://relay/telemetry
      this.token = o.token || ''            // JWT do usuário / do dispositivo
      this.ws = null
      this.onFix = null
      this._info = { source: 'safeboat', boatId: this.boatId, sensors: o.sensors || { gps: true, heading: true, depth: false, wind: false } }
    }
    info() { return this._info }
    start(onFix) {
      this.onFix = onFix
      // TODO(dev do MAIN): abrir o WebSocket real e mapear a mensagem do
      // dispositivo para o contrato de fix. Exemplo de forma esperada:
      //
      //   const WS = (typeof WebSocket !== 'undefined') ? WebSocket : require('ws')
      //   this.ws = new WS(`${this.wsUrl}?token=${this.token}&boat=${this.boatId}`)
      //   this.ws.onmessage = (ev) => {
      //     const m = JSON.parse(ev.data)   // telemetria do SAFEBOAT
      //     this.onFix({
      //       t: m.ts ?? Date.now(),
      //       lat: m.gps.lat, lon: m.gps.lon,
      //       accuracy: m.gps.acc ?? m.gps.hdop * 5,
      //       heading: m.ahrs?.heading ?? null,
      //       cog: m.gps.cog ?? null, sog: m.gps.sog ?? null,
      //       depth: m.sounder?.depth ?? null,
      //       novalid: (m.gps.fix ?? 1) < 1,
      //     })
      //   }
      //
      // O SAFEBOAT também pode empurrar o SNAPSHOT já decidido (estado do
      // alarme, âncora, raio) para o app não precisar recalcular — nesse caso
      // use onSnapshot em vez de onFix. Ver README.
      throw new Error('SafeboatAdapter é um stub — conectar ao dispositivo real no MAIN. Use SimAdapter no protótipo.')
    }
    stop() { if (this.ws) { try { this.ws.close() } catch (e) {} this.ws = null } }
  }

  /** fábrica: escolhe o adaptador pela config (o app decide em runtime) */
  function makeAdapter(opts) {
    const o = opts || {}
    if (o.source === 'safeboat') return new SafeboatAdapter(o)
    return new SimAdapter(o)
  }

  return { SimAdapter, SafeboatAdapter, makeAdapter }
})

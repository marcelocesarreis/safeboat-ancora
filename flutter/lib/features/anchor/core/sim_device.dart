/// SAFEBOAT — Dispositivo simulado (porta fiel de sim-device.js).
///
/// Barco fundeado/preso em poita com os fenômenos que fazem os alarmes de
/// celular tocar à toa (guinada, rajada, ronda de vento, maré, multipath) e os
/// que TÊM que alarmar (garrar, romper poita). Saída idêntica ao contrato de
/// `GpsFix`, então trocar simulação por SAFEBOAT real não mexe na UI nem no
/// núcleo de decisão.
library;

import 'dart:math' as math;

import 'anchor_core.dart' show GpsFix;
import 'geo.dart';

/// PRNG com semente (mulberry32) — a mesma simulação repete igual, essencial
/// para comparar ajustes de parâmetro. Reproduz bit-a-bit a aritmética uint32
/// do JS (validado contra o golden por `test/anchor_core_test.dart`).
///
/// Cuidados de porte JS→Dart: `>>>` do JS opera em uint32; em Dart o int é
/// 64-bit, então mascaramos com & 0xFFFFFFFF antes de deslocar; `|0`/`>>>0` do
/// JS viram toSigned(32)/& 0xFFFFFFFF; e Math.imul é o multiplicador 32-bit.
class Mulberry32 {
  int _a;
  Mulberry32(int seed) : _a = seed & 0xFFFFFFFF;

  /// Equivalente a Math.imul (multiplicação 32-bit, resultado int32).
  static int _imul(int a, int b) {
    a &= 0xFFFFFFFF;
    b &= 0xFFFFFFFF;
    final ah = (a >>> 16) & 0xFFFF, al = a & 0xFFFF;
    final bh = (b >>> 16) & 0xFFFF, bl = b & 0xFFFF;
    final hi = ((ah * bl + al * bh) & 0xFFFFFFFF) << 16;
    return ((al * bl + hi) & 0xFFFFFFFF).toSigned(32);
  }

  double next() {
    _a = (_a + 0x6D2B79F5) & 0xFFFFFFFF; // JS: a |= 0; a = (a + K) | 0
    final a = _a;
    final t1 = _imul(a ^ (a >>> 15), 1 | a);
    final u = t1 & 0xFFFFFFFF;
    final inner = _imul(u ^ (u >>> 7), 61 | u);
    final t = (((t1 + inner) & 0xFFFFFFFF) ^ u).toSigned(32);
    final tu = t & 0xFFFFFFFF;
    return ((tu ^ (tu >>> 14)) & 0xFFFFFFFF) / 4294967296;
  }
}

/// Ruído gaussiano (Box-Muller).
double gauss(Mulberry32 rnd) {
  double u = 0, v = 0;
  while (u == 0) {
    u = rnd.next();
  }
  while (v == 0) {
    v = rnd.next();
  }
  return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Forçantes do ambiente num instante.
class Env {
  double windDir, windSpd, gust, currentDir, currentSpd, dragRate, tide;
  bool multipath, gpsFail;
  Env({
    this.windDir = 0,
    this.windSpd = 0,
    this.gust = 0,
    this.currentDir = 0,
    this.currentSpd = 0,
    this.dragRate = 0,
    this.tide = 0,
    this.multipath = false,
    this.gpsFail = false,
  });
}

/// Definição de um cenário.
class Scenario {
  final String key;
  final String nome;
  final String desc;
  final String esperado;
  final bool mooring;
  final Env Function(double min) env;
  const Scenario(this.key, this.nome, this.desc, this.esperado, this.mooring, this.env);
}

/// Os 10 cenários (mesmos do JS).
final Map<String, Scenario> scenarios = {
  'calma': Scenario('calma', 'Noite calma',
      'Vento fraco e constante, 8-12 nós. O caso normal: não pode tocar alarme nenhum.',
      'sem alarme', false,
      (min) => Env(windDir: 135, windSpd: 5, gust: 1.5)),
  'rajadas': Scenario('rajadas', 'Frente com rajadas',
      'Vento sobe de 12 para 35 nós em rajadas. O barco retesa a amarra e chega no limite do raio — armadilha clássica de falso alarme.',
      'atenção sim, alarme não', false, (min) {
    final ramp = math.min(1, min / 25);
    return Env(windDir: 150 + 8 * math.sin(min / 6), windSpd: 6 + 12 * ramp, gust: 2 + 8 * ramp);
  }),
  'ronda-vento': Scenario('ronda-vento', 'Ronda de vento 180°',
      'Vento roda de S para N ao longo de 40 min. O barco atravessa o círculo inteiro e vai parar do lado oposto — distância da âncora quase não muda, mas o rumo inverte.',
      'sem alarme', false,
      (min) => Env(windDir: 180 + 180 * _clamp01((min - 20) / 40), windSpd: 7, gust: 2.5)),
  'mare': Scenario('mare', 'Inversão de maré',
      'Corrente inverte 180° e a profundidade varia 1,8 m. Barco gira em torno da âncora e o scope efetivo muda com a maré.',
      'sem alarme', false, (min) {
    final phase = (min / 60) * math.pi;
    return Env(
      windDir: 90, windSpd: 3.5, gust: 1.2,
      currentDir: min < 45 ? 70 : 250, currentSpd: 0.55 * math.cos(phase).abs(),
      tide: 0.9 * math.sin(phase),
    );
  }),
  'multipath': Scenario('multipath', 'Multipath perto do cais',
      'Fundeado junto a um costão/cais alto: o GPS dá saltos de 15-30 m e a precisão relatada piora. Ninguém pode ser acordado por isso.',
      'sem alarme', false,
      (min) => Env(windDir: 120, windSpd: 5, gust: 2, multipath: true)),
  'garrando': Scenario('garrando', 'Garrando de verdade',
      'Vento forte e a âncora não pegou: sai andando a 2,5 m/min para sotavento. É o alarme que tem que tocar, e rápido.',
      'ALARME', false,
      (min) => Env(windDir: 160, windSpd: 13, gust: 5, dragRate: min > 12 ? 2.5 : 0)),
  'garrando-lento': Scenario('garrando-lento', 'Garrando devagar',
      'A âncora escorrega 0,4 m/min. Durante muitos minutos o barco continua DENTRO do raio — só o centro do giro migra. Alarme por raio só percebe tarde demais.',
      'ALARME (pelo centro migrando)', false,
      (min) => Env(windDir: 200, windSpd: 9, gust: 3, dragRate: min > 10 ? 0.4 : 0)),
  'poita': Scenario('poita', 'Poita (boia de amarração)',
      'Preso numa poita com cabo curto. O raio é pequeno e o barco dá volta completa com a maré. Sem scope para calcular — o raio é cabo + comprimento do barco.',
      'sem alarme', true,
      (min) => Env(windDir: (40 + min * 4) % 360, windSpd: 4.5, gust: 2)),
  'poita-rompida': Scenario('poita-rompida', 'Poita rompida / cabo partido',
      'O cabo da poita parte e o barco sai à deriva com vento e corrente. Aceleração clara, sem volta.',
      'ALARME', true,
      (min) => Env(windDir: 70, windSpd: 8, gust: 3, currentDir: 60, currentSpd: min > 15 ? 0.6 : 0, dragRate: min > 15 ? 9 : 0)),
  'perda-sinal': Scenario('perda-sinal', 'Perda de sinal de GPS',
      'Antena obstruída: a precisão degrada e depois some. O sistema tem que avisar que está vigiando às cegas, não fingir que está tudo bem.',
      'aviso de sinal', false,
      (min) => Env(windDir: 130, windSpd: 6, gust: 2, gpsFail: min > 18 && min < 34)),
};

/// Verdade fundamental (só a simulação sabe; a UI usa para conferir).
class Truth {
  final Vec anchor;
  final Vec boat;
  final double dragged;
  final double windDir;
  final double windSpd;
  final double forceDir;
  final double rMax;
  final double depth;
  const Truth(this.anchor, this.boat, this.dragged, this.windDir, this.windSpd, this.forceDir, this.rMax, this.depth);
}

/// Um fix da simulação, com a verdade anexada.
class SimFix {
  final GpsFix fix;
  final Truth truth;
  const SimFix(this.fix, this.truth);
}

/// Física simplificada de um barco no fundeio.
class SimulatedBoat {
  Geo origin;
  double boatLength, antennaToBow, rodeLength, depth, bowRoller, windage;
  String scenario;
  final Mulberry32 rnd;
  final int t0;

  double tMin = 0;
  Vec anchor = const Vec(0, 0); // pode migrar se garrar
  Vec pos = const Vec(0, 0); // proa
  double yawPhase = 0;
  double radiusState = 0;
  double heading = 0;
  late double baseDepth;

  SimulatedBoat({
    this.origin = const Geo(-27.5954, -48.5480), // Florianópolis
    this.boatLength = 8,
    this.antennaToBow = 4,
    this.rodeLength = 40,
    this.depth = 6,
    this.bowRoller = 1.2,
    this.windage = 1,
    this.scenario = 'calma',
    int seed = 1234,
    int? t0,
  })  : rnd = Mulberry32(seed),
        t0 = t0 ?? DateTime.now().millisecondsSinceEpoch {
    baseDepth = depth;
    yawPhase = rnd.next() * math.pi * 2;
  }

  void reset() {
    tMin = 0;
    anchor = const Vec(0, 0);
    pos = const Vec(0, 0);
    yawPhase = rnd.next() * math.pi * 2;
    radiusState = 0;
    heading = 0;
    baseDepth = depth;
  }

  double maxRadius([double? d]) {
    final sc = scenarios[scenario];
    if (sc != null && sc.mooring) return rodeLength + boatLength * 0.15;
    final vertical = (d ?? depth) + bowRoller;
    final l = rodeLength;
    return l > vertical ? math.sqrt(l * l - vertical * vertical) : 0;
  }

  SimFix step(double dt) {
    tMin += dt / 60;
    final sc = scenarios[scenario] ?? scenarios['calma']!;
    final env = sc.env(tMin);
    final d = baseDepth + env.tide;

    final gust = env.windSpd + env.gust * math.max(0, gauss(rnd)) * (0.6 + 0.4 * math.sin(tMin * 1.7));
    final wx = math.sin(env.windDir * d2r) * gust;
    final wy = math.cos(env.windDir * d2r) * gust;
    final cx = math.sin(env.currentDir * d2r) * env.currentSpd * 6;
    final cy = math.cos(env.currentDir * d2r) * env.currentSpd * 6;
    final fx = wx + cx, fy = wy + cy;
    final force = math.sqrt(fx * fx + fy * fy);
    final forceDir = (math.atan2(fx, fy) * r2d + 360) % 360;

    if (env.dragRate != 0) {
      final dd = (env.dragRate * dt) / 60;
      anchor = Vec(anchor.x + math.sin(forceDir * d2r) * dd, anchor.y + math.cos(forceDir * d2r) * dd);
    }

    final rMax = maxRadius(d);
    final tension = _clamp01(math.pow(force / 12, 1.4).toDouble());
    final rTarget = rMax * (0.42 + 0.58 * tension);
    radiusState += (rTarget - radiusState) * math.min(1, dt / 40);

    yawPhase += (dt / (75 + 40 * rnd.next())) * math.pi;
    final yawAmp = (sc.mooring ? 12 : 22) * windage * (0.5 + 0.5 * _clamp01(force / 10));
    final yaw = yawAmp * math.sin(yawPhase) + 3 * gauss(rnd);

    final brg = forceDir + yaw;
    final target = Vec(
      anchor.x + math.sin(brg * d2r) * radiusState,
      anchor.y + math.cos(brg * d2r) * radiusState,
    );
    final k = math.min(1, dt / 22);
    pos = Vec(pos.x + (target.x - pos.x) * k, pos.y + (target.y - pos.y) * k);

    final toAnchor = math.atan2(anchor.x - pos.x, anchor.y - pos.y) * r2d;
    heading = (toAnchor + 360) % 360;

    final antX = pos.x - math.sin(heading * d2r) * antennaToBow;
    final antY = pos.y - math.cos(heading * d2r) * antennaToBow;

    var acc = 3.2 + 1.4 * gauss(rnd).abs();
    var nx = gauss(rnd) * acc * 0.5, ny = gauss(rnd) * acc * 0.5;
    if (env.multipath && rnd.next() < 0.035) {
      final spike = 12 + rnd.next() * 20;
      final sdir = rnd.next() * 360;
      nx += math.sin(sdir * d2r) * spike;
      ny += math.cos(sdir * d2r) * spike;
      acc = 14 + rnd.next() * 12;
    }
    final novalid = env.gpsFail;
    if (env.gpsFail) acc = 40 + rnd.next() * 30;

    final m = metersPerDegree(origin.lat);
    final fix = GpsFix(
      t: (t0 + tMin * 60000).round(),
      lat: origin.lat + (antY + ny) / m.lat,
      lon: origin.lon + (antX + nx) / m.lon,
      accuracy: double.parse(acc.toStringAsFixed(1)),
      heading: double.parse(heading.toStringAsFixed(1)),
      cog: double.parse(heading.toStringAsFixed(1)),
      sog: double.parse((math.sqrt(math.pow(target.x - pos.x, 2) + math.pow(target.y - pos.y, 2)) / math.max(dt, 1)).toStringAsFixed(2)),
      depth: double.parse(d.toStringAsFixed(1)),
      novalid: novalid,
    );
    final truth = Truth(anchor, pos, math.sqrt(anchor.x * anchor.x + anchor.y * anchor.y), env.windDir, gust, forceDir, rMax, d);
    return SimFix(fix, truth);
  }

  Geo truthAnchorLatLon() {
    final m = metersPerDegree(origin.lat);
    return Geo(origin.lat + anchor.y / m.lat, origin.lon + anchor.x / m.lon);
  }
}

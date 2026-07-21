/// SAFEBOAT — Núcleo da Âncora Virtual (porta fiel de anchor-core.js).
///
/// Puro, sem Flutter. Mesma lógica validada em `test-scenarios.cjs` /
/// `test-sweep.cjs` (0 falso alarme em 280 fundeios, 0 garradas perdidas em
/// 120). O teste de paridade `test/anchor_core_test.dart` confere este port
/// contra vetores-golden gerados pelo JS.
///
/// Diferença de projeto vs apps de celular: o SAFEBOAT é FIXO A BORDO — vigia
/// 24/7 com o app fechado; a antena não sai quando o dono desce em terra; e o
/// rastro contínuo permite ESTIMAR a âncora ajustando um círculo ao arco de giro.
library;

import 'dart:math' as math;

import 'geo.dart';

enum AnchorState { idle, setting, armed, prealarm, alarm, nosignal }

String anchorStateName(AnchorState s) => switch (s) {
      AnchorState.idle => 'idle',
      AnchorState.setting => 'setting',
      AnchorState.armed => 'armed',
      AnchorState.prealarm => 'prealarm',
      AnchorState.alarm => 'alarm',
      AnchorState.nosignal => 'nosignal',
    };

/// Um fix de posição — o contrato que todo dispositivo (simulado ou SAFEBOAT
/// real) entrega. Ver device_adapter.dart.
class GpsFix {
  final int t; // epoch ms
  final double lat;
  final double lon;
  final double accuracy; // m
  final double? heading; // ° 0..360 (proa)
  final double? cog;
  final double? sog; // m/s
  final double? depth; // m
  final bool novalid;

  const GpsFix({
    required this.t,
    required this.lat,
    required this.lon,
    this.accuracy = 8,
    this.heading,
    this.cog,
    this.sog,
    this.depth,
    this.novalid = false,
  });

  Geo get geo => Geo(lat, lon);
}

/// Configuração do fundeio (calibração de instalação + informado pelo usuário).
class AnchorConfig {
  double boatLength;
  double antennaToBow;
  double rodeLength;
  double depth;
  double bowRoller;
  double gpsMargin;
  double? alarmRadius; // null = calculado por swingRadius

  // --- detecção (mesmos DEFAULTS do JS) ---
  double confirmSeconds;
  double prealarmFraction;
  double driftWindowMin;
  double driftThreshold;
  double maxFixAgeSec;
  double accuracyLimit;
  double speedGate;
  bool autoFitAnchor;
  double holdOffSeconds;

  AnchorConfig({
    this.boatLength = 8,
    this.antennaToBow = 4,
    this.rodeLength = 40,
    this.depth = 6,
    this.bowRoller = 1.2,
    this.gpsMargin = 5,
    this.alarmRadius,
    this.confirmSeconds = 45,
    this.prealarmFraction = 0.85,
    this.driftWindowMin = 20,
    this.driftThreshold = 0.15,
    this.maxFixAgeSec = 30,
    this.accuracyLimit = 25,
    this.speedGate = 4.1,
    this.autoFitAnchor = true,
    this.holdOffSeconds = 90,
  });

  AnchorConfig clone() => AnchorConfig(
        boatLength: boatLength,
        antennaToBow: antennaToBow,
        rodeLength: rodeLength,
        depth: depth,
        bowRoller: bowRoller,
        gpsMargin: gpsMargin,
        alarmRadius: alarmRadius,
        confirmSeconds: confirmSeconds,
        prealarmFraction: prealarmFraction,
        driftWindowMin: driftWindowMin,
        driftThreshold: driftThreshold,
        maxFixAgeSec: maxFixAgeSec,
        accuracyLimit: accuracyLimit,
        speedGate: speedGate,
        autoFitAnchor: autoFitAnchor,
        holdOffSeconds: holdOffSeconds,
      );

  double get radius => alarmRadius ??
      swingRadius(
        rodeLength: rodeLength,
        depth: depth,
        bowRoller: bowRoller,
        boatLength: boatLength,
        gpsMargin: gpsMargin,
      );

  double get scope => scopeRatio(rodeLength: rodeLength, depth: depth, bowRoller: bowRoller);
}

/// Deriva do centro de giro — o diferencial sobre alarmes só de raio.
class DriftInfo {
  final double rate; // m/min do centro de giro
  final double bearing; // ° da deriva
  final double tVel;
  final double tRad;
  final bool significant;
  final double accumulated; // m migrados desde o início da deriva
  final double sinceMin;
  final double radiusRate;
  final double radialAlign;

  const DriftInfo({
    this.rate = 0,
    this.bearing = 0,
    this.tVel = 0,
    this.tRad = 0,
    this.significant = false,
    this.accumulated = 0,
    this.sinceMin = 0,
    this.radiusRate = 0,
    this.radialAlign = 0,
  });

  /// alias usado pela UI: deslocamento acumulado do centro
  double get dist => accumulated;
  bool get confident => significant;
}

/// Ponto do rastro filtrado.
class TrackPoint {
  final int t;
  final double x;
  final double y;
  final double r;
  final double brg;
  final double acc;
  const TrackPoint(this.t, this.x, this.y, this.r, this.brg, this.acc);
}

/// Evento para a UI/telemetria.
class AnchorEvent {
  final int t;
  final String kind;
  final String text;
  const AnchorEvent(this.t, this.kind, this.text);
}

/// Snapshot completo da vigília — o que a UI desenha.
class AnchorSnapshot {
  final AnchorState state;
  final Geo? anchor;
  final String? anchorSource;
  final double radius;
  final double scope;
  final Geo? position;
  final double distance;
  final double bearing;
  final double usage;
  final double maxRadiusSeen;
  final DriftInfo drift;
  final int outsideFor;
  final double? accuracy;
  final double? heading;
  final double? sog;
  final double? depth;
  final int? t;

  const AnchorSnapshot({
    required this.state,
    this.anchor,
    this.anchorSource,
    required this.radius,
    required this.scope,
    this.position,
    this.distance = 0,
    this.bearing = 0,
    this.usage = 0,
    this.maxRadiusSeen = 0,
    this.drift = const DriftInfo(),
    this.outsideFor = 0,
    this.accuracy,
    this.heading,
    this.sog,
    this.depth,
    this.t,
  });

  bool get isActive => state != AnchorState.idle;
  bool get isAlarming => state == AnchorState.alarm;
}

/// Filtro de posição adaptativo (peso do fix cai com precisão ruim; salto
/// fisicamente impossível é descartado). Leve de propósito — roda em
/// microcontrolador.
class PositionFilter {
  final AnchorConfig cfg;
  Vec? est;
  int? lastT;
  int rejected = 0;
  PositionFilter(this.cfg);

  void reset() {
    est = null;
    lastT = null;
    rejected = 0;
  }

  Vec push(Vec local, int t, double? accuracy) {
    final acc = accuracy ?? 8;
    if (est == null) {
      est = local;
      lastT = t;
      return est!;
    }
    final dt = math.max(0.2, (t - lastT!) / 1000);
    final jump = math.sqrt(math.pow(local.x - est!.x, 2) + math.pow(local.y - est!.y, 2)).toDouble();
    if (jump / dt > cfg.speedGate && rejected < 5) {
      rejected++;
      return est!;
    }
    rejected = 0;
    final alpha = math.max(0.08, math.min(0.5, 1.6 / (acc + 1.5)));
    est = Vec(est!.x + alpha * (local.x - est!.x), est!.y + alpha * (local.y - est!.y));
    lastT = t;
    return est!;
  }
}

/// Máquina de estados da vigília de âncora.
class AnchorWatch {
  AnchorConfig cfg;

  AnchorState state = AnchorState.idle;
  Geo? anchor;
  Geo? anchorOrigin; // base da trava cumulativa do refino
  String? anchorSource;
  Geo? ref;
  late PositionFilter filter;
  final List<TrackPoint> track = [];
  final List<AnchorEvent> events = [];
  int? armedAt;
  int? outsideSince;
  GpsFix? lastFix;
  double maxRadiusSeen = 0;
  DriftInfo drift = const DriftInfo();
  Vec? driftRef; // referência do início da deriva
  int? driftRefT;
  int? driftLostAt;
  CircleFit? fitted;
  int fixes = 0;
  int rejectedFixes = 0;

  AnchorWatch(AnchorConfig config) : cfg = config {
    filter = PositionFilter(cfg);
  }

  double get radius => cfg.radius;

  // ---- configuração ----

  void setConfig(void Function(AnchorConfig) patch) => patch(cfg);

  // ---- ciclo de vida ----

  Geo dropAnchor(GpsFix fix) {
    final bow = _bowPosition(fix);
    anchor = bow;
    anchorOrigin = bow;
    anchorSource = 'marcado';
    ref = bow;
    filter.reset();
    track.clear();
    maxRadiusSeen = 0;
    state = AnchorState.setting;
    lastFix = fix;
    _event('ancora', 'Âncora lançada — verificando aguante');
    return anchor!;
  }

  /// Define a âncora e REINICIA o quadro de referência (antes de qualquer fix —
  /// testes, estimativa retroativa). Limpa o filtro.
  Geo setAnchor(Geo pos, [String? source]) {
    anchor = pos;
    if (source != 'ajuste-arco') anchorOrigin = pos;
    anchorSource = source ?? 'manual';
    ref = pos;
    filter.reset();
    maxRadiusSeen = 0;
    _event('ancora', 'Posição da âncora ajustada');
    return anchor!;
  }

  /// Reposiciona a âncora SEM perder o rastro nem o quadro de referência — o
  /// caso comum: ligar o alarme já fundeado e ARRASTAR o pino até o ponto real
  /// no fundo. O rastro é gravado no quadro `ref` (fixo desde o lançamento),
  /// então mover a âncora só muda de onde as distâncias são medidas. Zera o que
  /// dependia da âncora antiga para não alarmar por causa do reposicionamento.
  Geo moveAnchor(Geo pos) {
    ref ??= pos;
    anchor = pos;
    anchorOrigin = pos;
    anchorSource = 'manual';
    outsideSince = null;
    driftRef = null;
    driftLostAt = null;
    driftRefT = null;
    _noDrift();
    maxRadiusSeen = 0;
    return anchor!;
  }

  /// Distância linear (m) de uma posição de âncora hipotética até o barco (usado
  /// enquanto o usuário arrasta o pino).
  double anchorToBoat(Geo anchorPos) {
    if (lastFix == null) return 0;
    return distance(anchorPos, _bowPosition(lastFix!));
  }

  /// Estima a âncora a partir de um rastro já gravado (dispositivo de bordo
  /// vigia desde antes). Ajusta um círculo ao arco de giro.
  ({Geo pos, bool confident, double span, double radius})? anchorFromTrack(List<Geo> trackFixes) {
    if (trackFixes.length < 12) return null;
    final r = trackFixes[0];
    final pts = trackFixes.map((f) => toLocal(r, f)).toList();
    final fit = fitCircle(pts);
    if (fit == null) return null;
    final pos = fromLocal(r, Vec(fit.x, fit.y));
    if (fit.span < 70) {
      final c = centroid(pts);
      setAnchor(fromLocal(r, c), 'retroativo');
      fitted = fit;
      return (pos: anchor!, confident: false, span: fit.span, radius: fit.r);
    }
    setAnchor(pos, 'ajuste-arco');
    fitted = fit;
    return (pos: pos, confident: true, span: fit.span, radius: fit.r);
  }

  bool arm() {
    if (anchor == null) return false;
    state = AnchorState.armed;
    armedAt = lastFix?.t ?? DateTime.now().millisecondsSinceEpoch;
    outsideSince = null;
    _event('armado', 'Alarme ativo — raio ${radius.round()} m');
    return true;
  }

  void disarm() {
    state = AnchorState.idle;
    outsideSince = null;
    _event('desarmado', 'Alarme desativado');
  }

  void acknowledge() {
    if (state == AnchorState.alarm || state == AnchorState.prealarm) {
      state = AnchorState.armed;
      outsideSince = null;
      _event('reconhecido', 'Alarme reconhecido pelo tripulante');
    }
  }

  // ---- alimentação ----

  AnchorSnapshot feed(GpsFix fix) {
    fixes++;
    lastFix = fix;
    if (fix.depth != null && state == AnchorState.setting) cfg.depth = fix.depth!;

    if (anchor == null) return snapshot();
    ref ??= anchor;

    final bow = _bowPosition(fix);
    final local = toLocal(ref!, bow);
    final before = filter.est;
    final est = filter.push(local, fix.t, fix.accuracy);
    if (before != null && identical(est, before)) rejectedFixes++;

    final anchorLocal = toLocal(ref!, anchor!);
    final dx = est.x - anchorLocal.x, dy = est.y - anchorLocal.y;
    final r = math.sqrt(dx * dx + dy * dy);
    final brg = (math.atan2(dx, dy) * r2d + 360) % 360;

    track.add(TrackPoint(fix.t, est.x, est.y, r, brg, fix.accuracy));
    if (track.length > 4000) track.removeRange(0, track.length - 4000);
    if (state != AnchorState.setting) maxRadiusSeen = math.max(maxRadiusSeen, r);

    _updateDrift();
    if (cfg.autoFitAnchor) _maybeRefineAnchor();
    _evaluate(fix, r);
    return snapshot();
  }

  // ---- interno ----

  Geo _bowPosition(GpsFix fix) {
    final hdg = fix.heading ?? fix.cog;
    if (hdg == null || cfg.antennaToBow == 0) return fix.geo;
    return destination(fix.geo, cfg.antennaToBow, hdg);
  }

  void _event(String kind, String text) {
    final t = lastFix?.t ?? DateTime.now().millisecondsSinceEpoch;
    events.add(AnchorEvent(t, kind, text));
    if (events.length > 200) events.removeAt(0);
  }

  void _noDrift() => drift = const DriftInfo();

  /// Detector de deriva lenta do CENTRO de giro (o coração da coisa).
  ///
  /// Média em blocos de 2 min (mata a autocorrelação da guinada) + regressão
  /// linear com teste de significância + teste RADIAL vs TANGENCIAL (barco
  /// girando em torno da âncora move-se tangencialmente; garrando, radialmente).
  /// É o que separa ronda de vento/maré (falso alarme nº 1 dos apps) de garrada.
  void _updateDrift() {
    final win = cfg.driftWindowMin * 60000;
    final now = track.last.t;
    final recent = <TrackPoint>[];
    for (var i = track.length - 1; i >= 0; i--) {
      if (now - track[i].t > win) break;
      recent.add(track[i]);
    }
    final rev = recent.reversed.toList();
    if (rev.length < 90) return _noDrift();

    // médias em blocos de 2 min
    const block = 120000;
    final t0 = rev.first.t;
    final acc = <int, List<double>>{}; // k -> [n,x,y,r,t]
    for (final p in rev) {
      final k = ((p.t - t0) / block).floor();
      final b = acc.putIfAbsent(k, () => [0, 0, 0, 0, 0]);
      b[0] += 1;
      b[1] += p.x;
      b[2] += p.y;
      b[3] += p.r;
      b[4] += p.t.toDouble();
    }
    final keys = acc.keys.toList()..sort();
    final bAvg = <_Block>[];
    for (final k in keys) {
      final b = acc[k]!;
      if (b[0] >= 40) bAvg.add(_Block(b[1] / b[0], b[2] / b[0], b[3] / b[0], b[4] / b[0]));
    }
    if (bAvg.length < 5) return _noDrift();

    final rx = _reg(bAvg, (b) => b.x);
    final ry = _reg(bAvg, (b) => b.y);
    final rr = _reg(bAvg, (b) => b.r);

    final rate = math.sqrt(rx.slope * rx.slope + ry.slope * ry.slope);
    final seV = math.sqrt(rx.se * rx.se + ry.se * ry.se);
    final seVv = seV == 0 ? 1e-9 : seV;
    final tVel = rate / seVv;
    final tRad = (rr.se > 0 && rr.se.isFinite) ? rr.slope / rr.se : 0.0;
    final brg = (math.atan2(rx.slope, ry.slope) * r2d + 360) % 360;

    // radial vs tangencial contra a direção MÉDIA da janela
    final anchorLocal = toLocal(ref!, anchor!);
    final cen = centroid(rev.map((p) => Vec(p.x, p.y)).toList());
    final meanBrg = (math.atan2(cen.x - anchorLocal.x, cen.y - anchorLocal.y) * r2d + 360) % 360;
    final radialAlign = math.cos(angleDiff(brg, meanBrg) * d2r);

    final significant = tVel > 2.0 && tRad > 1.0 && rate > 0.08 && radialAlign > 0.6;

    final head = bAvg.first, tail = bAvg.last;
    if (significant) {
      if (driftRef == null) {
        driftRef = Vec(head.x, head.y);
        driftRefT = head.t.round();
      }
      driftLostAt = null;
    } else if (driftRef != null) {
      if (driftLostAt == null) {
        driftLostAt = now;
      } else if (now - driftLostAt! > 6 * 60000) {
        driftRef = null;
        driftLostAt = null;
        driftRefT = null;
      }
    }
    final accumulated = driftRef != null
        ? math.sqrt(math.pow(tail.x - driftRef!.x, 2) + math.pow(tail.y - driftRef!.y, 2)).toDouble()
        : 0.0;

    drift = DriftInfo(
      rate: rate,
      bearing: brg,
      tVel: tVel,
      tRad: tRad.toDouble(),
      significant: significant,
      accumulated: accumulated,
      sinceMin: driftRefT != null ? (now - driftRefT!) / 60000 : 0,
      radiusRate: rr.slope,
      radialAlign: radialAlign,
    );
  }

  _Reg _reg(List<_Block> b, double Function(_Block) key) {
    final n = b.length;
    final base = b.first.t;
    double st = 0, sv = 0, stt = 0, stv = 0;
    for (final e in b) {
      final tt = (e.t - base) / 60000;
      final v = key(e);
      st += tt;
      sv += v;
      stt += tt * tt;
      stv += tt * v;
    }
    final den = n * stt - st * st;
    if (den.abs() < 1e-9) return const _Reg(0, double.infinity);
    final slope = (n * stv - st * sv) / den;
    final icpt = (sv - slope * st) / n;
    double sse = 0;
    for (final e in b) {
      final tt = (e.t - base) / 60000;
      sse += math.pow(key(e) - (icpt + slope * tt), 2).toDouble();
    }
    final se = math.sqrt((sse / math.max(1, n - 2)) * n / den);
    return _Reg(slope, se);
  }

  void _maybeRefineAnchor() {
    if (state != AnchorState.armed) return;
    if (drift.significant) return;
    if (track.length < 120 || track.length % 60 != 0) return;

    final recent = track.length > 900 ? track.sublist(track.length - 900) : track.toList();
    final fit = fitCircle(recent.map((p) => Vec(p.x, p.y)).toList());
    if (fit == null) return;
    final expected = radius;
    final confident = fit.span >= 90 && fit.rms < 6 && fit.r < expected * 1.3;
    fitted = fit;
    if (!confident) return;

    final anchorLocal = toLocal(ref!, anchor!);
    final move = math.sqrt(math.pow(fit.x - anchorLocal.x, 2) + math.pow(fit.y - anchorLocal.y, 2));
    if (move > expected * 0.2) return;

    final originLocal = toLocal(ref!, anchorOrigin ?? anchor!);
    final total = math.sqrt(math.pow(fit.x - originLocal.x, 2) + math.pow(fit.y - originLocal.y, 2));
    if (total > expected * 0.25) return;

    anchor = fromLocal(ref!, Vec(fit.x, fit.y));
    anchorSource = 'ajuste-arco';
  }

  void _evaluate(GpsFix fix, double r) {
    if (state == AnchorState.idle) return;

    final bad = fix.accuracy > cfg.accuracyLimit;
    if (fix.novalid || bad) {
      if (state == AnchorState.armed || state == AnchorState.prealarm) {
        state = AnchorState.nosignal;
        _event('sinal', 'Sinal de GPS degradado — vigília em dúvida');
      }
      return;
    }
    if (state == AnchorState.nosignal) {
      state = AnchorState.armed;
      _event('sinal', 'Sinal de GPS restabelecido');
    }

    if (state == AnchorState.setting) return;
    if (state != AnchorState.armed && state != AnchorState.prealarm && state != AnchorState.alarm) {
      return;
    }

    if (armedAt != null && fix.t - armedAt! < cfg.holdOffSeconds * 1000) return;

    final rr = radius;
    final hardLimit = rr + math.max(0, (fix.accuracy) - 5) * 0.8;

    if (r > hardLimit) {
      outsideSince ??= fix.t;
    } else if (r < rr * 0.92) {
      outsideSince = null;
    }

    final sustained = outsideSince != null && (fix.t - outsideSince!) >= cfg.confirmSeconds * 1000;
    final creepLimit = math.max(6, rr * cfg.driftThreshold);
    final creepFar = drift.significant && drift.accumulated > creepLimit;

    // limite do que a AMARRA consegue explicar (esticar satura; garrar não)
    final rodeLimit = swingRadius(rodeLength: cfg.rodeLength, depth: cfg.depth, bowRoller: cfg.bowRoller, boatLength: 0, gpsMargin: 0);
    final explainable = rodeLimit > 0 ? rodeLimit + cfg.gpsMargin : rr * 0.85;
    final creeping = creepFar && r > explainable;

    if (sustained || creeping) {
      if (state != AnchorState.alarm) {
        state = AnchorState.alarm;
        final motivo = sustained
            ? 'fora do raio há ${((fix.t - outsideSince!) / 1000).round()}s'
            : 'centro de giro migrou ${drift.accumulated.round()} m a ${drift.rate.toStringAsFixed(2)} m/min';
        _event('alarme', 'GARRANDO — $motivo');
      }
      return;
    }

    final nearLimit = r > rr * cfg.prealarmFraction;
    final creepSuspect = creepFar || (drift.significant && drift.accumulated > creepLimit * 0.45);
    if (nearLimit || creepSuspect) {
      if (state == AnchorState.armed) {
        state = AnchorState.prealarm;
        _event('atencao', creepSuspect ? 'Centro de giro migrando ${drift.rate.toStringAsFixed(2)} m/min' : 'Encostando no limite do raio');
      }
      return;
    }
    if (state == AnchorState.prealarm) {
      state = AnchorState.armed;
      _event('normal', 'Voltou para dentro do raio');
    }
  }

  // ---- saída ----

  AnchorSnapshot snapshot() {
    final last = track.isNotEmpty ? track.last : null;
    final rr = radius;
    // posição da proa: do rastro se houver, senão do fix atual — distância
    // correta mesmo SEM rastro (ex.: acabou de lançar e o mar está pausado
    // enquanto o usuário ARRASTA a âncora).
    Vec? boatLocal;
    if (last != null) {
      boatLocal = Vec(last.x, last.y);
    } else if (lastFix != null && ref != null) {
      boatLocal = toLocal(ref!, _bowPosition(lastFix!));
    }
    var dist = 0.0, brg = 0.0;
    if (boatLocal != null && anchor != null && ref != null) {
      final al = toLocal(ref!, anchor!);
      final dx = boatLocal.x - al.x, dy = boatLocal.y - al.y;
      dist = math.sqrt(dx * dx + dy * dy);
      brg = (math.atan2(dx, dy) * r2d + 360) % 360;
    }
    final Geo? posGeo = last != null
        ? fromLocal(ref!, Vec(last.x, last.y))
        : (lastFix != null && ref != null ? _bowPosition(lastFix!) : lastFix?.geo);
    return AnchorSnapshot(
      state: state,
      anchor: anchor,
      anchorSource: anchorSource,
      radius: rr,
      scope: cfg.scope,
      position: posGeo,
      distance: dist,
      bearing: brg,
      usage: math.min(1.5, dist / rr),
      maxRadiusSeen: maxRadiusSeen,
      drift: drift,
      outsideFor: (outsideSince != null && last != null) ? ((last.t - outsideSince!) / 1000).round() : 0,
      accuracy: lastFix?.accuracy,
      heading: lastFix?.heading,
      sog: lastFix?.sog,
      depth: cfg.depth,
      t: last?.t,
    );
  }

  /// Rastro em lat/lon para desenhar no mapa (subamostrado).
  List<Geo> trackLatLon([int maxPoints = 600]) {
    if (ref == null) return const [];
    final step = math.max(1, (track.length / maxPoints).ceil());
    final out = <Geo>[];
    for (var i = 0; i < track.length; i += step) {
      out.add(fromLocal(ref!, Vec(track[i].x, track[i].y)));
    }
    return out;
  }
}

class _Block {
  final double x, y, r, t;
  const _Block(this.x, this.y, this.r, this.t);
}

class _Reg {
  final double slope;
  final double se;
  const _Reg(this.slope, this.se);
}

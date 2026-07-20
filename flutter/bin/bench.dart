/// SAFEBOAT — Bancada de cenários em Dart (espelha test-scenarios.cjs).
///
///   dart run bin/bench.dart            # todos os cenários
///   dart run bin/bench.dart garrando   # um cenário, com detalhes
///
/// Prova que o stack Dart (núcleo + simulação) decide igual ao JS: benignos não
/// alarmam, garradas alarmam e rápido.
import 'dart:math' as math;

import 'package:safeboat_ancora/features/anchor/core/anchor_core.dart';
import 'package:safeboat_ancora/features/anchor/core/geo.dart';
import 'package:safeboat_ancora/features/anchor/core/sim_device.dart';

const durMin = 90;

final expect = <String, Map<String, dynamic>>{
  'calma': {'alarm': false},
  'rajadas': {'alarm': false},
  'ronda-vento': {'alarm': false},
  'mare': {'alarm': false},
  'multipath': {'alarm': false},
  'poita': {'alarm': false},
  'perda-sinal': {'alarm': false, 'noSignal': true},
  'garrando': {'alarm': true, 'dragStartsMin': 12, 'maxDetectMin': 8, 'maxDistM': 25},
  'garrando-lento': {'alarm': true, 'dragStartsMin': 10, 'maxDetectMin': 30, 'maxDistM': 20},
  'poita-rompida': {'alarm': true, 'dragStartsMin': 15, 'maxDetectMin': 4, 'maxDistM': 40},
};

class Result {
  String name = '';
  double? firstAlarm;
  double? firstPre;
  bool sawNoSignal = false;
  double? alarmAtDist;
  double maxDist = 0;
  double radius = 0;
  double anchorError = 0;
  List<String> transitions = [];
  List<AnchorEvent> events = [];
}

Result runScenario(String name, {int seed = 7}) {
  final sc = scenarios[name]!;
  final mooring = sc.mooring;
  final boat = SimulatedBoat(
    scenario: name, seed: seed,
    rodeLength: mooring ? 12 : 40, depth: 6, boatLength: 8, antennaToBow: 4,
  );
  final watch = AnchorWatch(AnchorConfig(
    boatLength: 8, antennaToBow: 4, rodeLength: mooring ? 12 : 40, depth: 6,
    alarmRadius: mooring ? 22 : null,
  ));

  SimFix? sf;
  for (var i = 0; i < 120; i++) {
    sf = boat.step(1);
  }
  watch.setAnchor(boat.truthAnchorLatLon(), 'marcado');
  watch.arm();
  watch.armedAt = sf!.fix.t;

  final r = Result()
    ..name = name
    ..radius = watch.radius;
  var lastState = AnchorState.armed;

  for (var i = 0; i < durMin * 60; i++) {
    sf = boat.step(1);
    final snap = watch.feed(sf.fix);
    final min = (sf.fix.t - watch.armedAt!) / 60000;
    if (snap.state != lastState) {
      r.transitions.add('${min.toStringAsFixed(1)}min ${anchorStateName(lastState)}→${anchorStateName(snap.state)} (dist ${snap.distance.toStringAsFixed(1)}m, deriva ${snap.drift.accumulated.toStringAsFixed(1)}m)');
      lastState = snap.state;
    }
    if (snap.state == AnchorState.nosignal) r.sawNoSignal = true;
    if (snap.state == AnchorState.prealarm && r.firstPre == null) r.firstPre = min;
    if (snap.state == AnchorState.alarm && r.firstAlarm == null) {
      r.firstAlarm = min;
      r.alarmAtDist = sf.truth.dragged;
    }
  }
  r.maxDist = watch.track.fold<double>(0.0, (a, p) => math.max(a, p.r));
  r.anchorError = distance(watch.anchor!, boat.truthAnchorLatLon());
  r.events = watch.events;
  return r;
}

({bool ok, String note}) judge(Result r) {
  final exp = expect[r.name];
  if (exp == null) return (ok: true, note: 'sem expectativa');
  final notes = <String>[];
  var ok = true;
  if (exp['alarm'] == true) {
    if (r.firstAlarm == null) {
      ok = false;
      notes.add('NÃO alarmou (deveria)');
    } else {
      final detectMin = r.firstAlarm! - ((exp['dragStartsMin'] as int) - 2);
      if (detectMin > (exp['maxDetectMin'] as int)) {
        ok = false;
        notes.add('demorou ${detectMin.toStringAsFixed(1)} min (limite ${exp['maxDetectMin']})');
      } else {
        notes.add('detectou em ${math.max(0, detectMin).toStringAsFixed(1)} min');
      }
      if (r.alarmAtDist != null) notes.add('âncora andou ${r.alarmAtDist!.round()} m');
    }
  } else {
    if (r.firstAlarm != null) {
      ok = false;
      notes.add('FALSO ALARME aos ${r.firstAlarm!.toStringAsFixed(1)} min');
    } else {
      notes.add('nenhum alarme (correto)');
    }
    if (r.firstPre != null) notes.add('atenção aos ${r.firstPre!.toStringAsFixed(1)} min');
    if (exp['noSignal'] == true && !r.sawNoSignal) {
      ok = false;
      notes.add('não sinalizou perda de GPS');
    }
  }
  return (ok: ok, note: notes.join(' · '));
}

void main(List<String> args) {
  final only = args.isNotEmpty ? args[0] : null;
  final names = only != null ? [only] : scenarios.keys.toList();
  var pass = 0, fail = 0;

  print('\nSAFEBOAT — bancada da âncora virtual (Dart)');
  print('$durMin min simulados por cenário · 1 Hz\n');

  for (final name in names) {
    if (!scenarios.containsKey(name)) {
      print('cenário desconhecido: $name');
      return;
    }
    final r = runScenario(name);
    final v = judge(r);
    v.ok ? pass++ : fail++;
    final tag = v.ok ? '  OK  ' : ' FALHA';
    print('$tag ${scenarios[name]!.nome}  (raio ${r.radius.round()} m, máx. ${r.maxDist.round()} m)');
    print('       ${v.note}');
    if (only != null) {
      print('       erro de posição da âncora: ${r.anchorError.toStringAsFixed(1)} m');
      print('\n       transições:');
      for (final t in r.transitions) {
        print('         $t');
      }
      print('\n       eventos:');
      for (final e in r.events) {
        print('         ${e.kind.padRight(12)} ${e.text}');
      }
    }
    print('');
  }
  print('$pass passou, $fail falhou\n');
}

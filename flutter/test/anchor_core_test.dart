/// Teste de PARIDADE: confere que o port Dart do núcleo reproduz o núcleo JS
/// já validado (0 falso alarme em 280 fundeios). Os vetores-golden são gerados
/// por `node gen-golden.cjs` a partir do JS e ficam em test/golden.json.
///
///   flutter test        (ou:  dart test)
///
/// Também roda uma bancada de cenários independente (mesmo espírito de
/// test-scenarios.cjs): benignos não alarmam, garradas alarmam.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:safeboat_ancora/features/anchor/core/anchor_core.dart';
import 'package:safeboat_ancora/features/anchor/core/geo.dart';
import 'package:safeboat_ancora/features/anchor/core/sim_device.dart';

void main() {
  final golden = jsonDecode(File('test/golden.json').readAsStringSync()) as Map<String, dynamic>;

  group('paridade com o núcleo JS', () {
    test('RNG mulberry32 é bit-idêntico', () {
      final g = golden['rng'] as Map<String, dynamic>;
      final rnd = Mulberry32(g['seed'] as int);
      final expected = (g['values'] as List).cast<num>();
      for (var i = 0; i < expected.length; i++) {
        expect(rnd.next(), closeTo(expected[i].toDouble(), 1e-15), reason: 'rng[$i]');
      }
    });

    test('gauss casa dentro de tolerância', () {
      final g = golden['gauss'] as Map<String, dynamic>;
      final rnd = Mulberry32(g['seed'] as int);
      final expected = (g['values'] as List).cast<num>();
      for (var i = 0; i < expected.length; i++) {
        expect(gauss(rnd), closeTo(expected[i].toDouble(), 1e-9), reason: 'gauss[$i]');
      }
    });

    test('swingRadius / scopeRatio', () {
      for (final e in (golden['swing'] as List).cast<Map<String, dynamic>>()) {
        final c = e['cfg'] as Map<String, dynamic>;
        final r = swingRadius(
          rodeLength: (c['rodeLength'] as num).toDouble(),
          depth: (c['depth'] as num).toDouble(),
          bowRoller: (c['bowRoller'] as num).toDouble(),
          boatLength: (c['boatLength'] as num).toDouble(),
          gpsMargin: (c['gpsMargin'] as num).toDouble(),
        );
        final s = scopeRatio(
          rodeLength: (c['rodeLength'] as num).toDouble(),
          depth: (c['depth'] as num).toDouble(),
          bowRoller: (c['bowRoller'] as num).toDouble(),
        );
        expect(r, closeTo((e['radius'] as num).toDouble(), 1e-9));
        expect(s, closeTo((e['scope'] as num).toDouble(), 1e-9));
      }
    });

    test('fitCircle sobre arco conhecido', () {
      final g = golden['fitCircle'] as Map<String, dynamic>;
      final pts = (g['pts'] as List)
          .map((p) => Vec((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
          .toList();
      final fit = fitCircle(pts)!;
      final exp = g['fit'] as Map<String, dynamic>;
      expect(fit.x, closeTo((exp['x'] as num).toDouble(), 1e-6));
      expect(fit.y, closeTo((exp['y'] as num).toDouble(), 1e-6));
      expect(fit.r, closeTo((exp['r'] as num).toDouble(), 1e-6));
      expect(fit.span, closeTo((exp['span'] as num).toDouble(), 1e-6));
    });

    test('trace do núcleo sobre fixes determinísticos', () {
      final tr = golden['trace'] as Map<String, dynamic>;
      final c = tr['config'] as Map<String, dynamic>;
      final fixes = (tr['fixes'] as List).map((f) {
        final m = f as Map<String, dynamic>;
        return GpsFix(
          t: m['t'] as int,
          lat: (m['lat'] as num).toDouble(),
          lon: (m['lon'] as num).toDouble(),
          accuracy: (m['accuracy'] as num).toDouble(),
          heading: (m['heading'] as num?)?.toDouble(),
          depth: (m['depth'] as num?)?.toDouble(),
        );
      }).toList();

      final watch = AnchorWatch(AnchorConfig(
        boatLength: (c['boatLength'] as num).toDouble(),
        antennaToBow: (c['antennaToBow'] as num).toDouble(),
        rodeLength: (c['rodeLength'] as num).toDouble(),
        depth: (c['depth'] as num).toDouble(),
        autoFitAnchor: c['autoFitAnchor'] as bool,
      ));
      watch.dropAnchor(fixes[0]);
      watch.arm();
      watch.armedAt = fixes[0].t;

      final samplesByIndex = {
        for (final s in (tr['samples'] as List).cast<Map<String, dynamic>>()) s['i'] as int: s
      };
      int? firstAlarm;
      for (var i = 0; i < fixes.length; i++) {
        final snap = watch.feed(fixes[i]);
        if (snap.state == AnchorState.alarm && firstAlarm == null) firstAlarm = i;
        final g = samplesByIndex[i];
        if (g != null) {
          expect(anchorStateName(snap.state), g['state'],
              reason: 'estado no fix $i');
          expect(snap.distance, closeTo((g['distance'] as num).toDouble(), 0.05),
              reason: 'distância no fix $i');
          expect(snap.drift.accumulated, closeTo((g['driftAccum'] as num).toDouble(), 0.2),
              reason: 'deriva acumulada no fix $i');
        }
      }
      // o índice do primeiro alarme deve casar (tolerância a ULP na regressão)
      expect(firstAlarm, isNotNull);
      expect((firstAlarm! - (tr['firstAlarmIndex'] as int)).abs(), lessThanOrEqualTo(5),
          reason: 'primeiro alarme JS=${tr['firstAlarmIndex']} Dart=$firstAlarm');
    });
  });

  group('bancada de cenários (independente do JS)', () {
    // benignos: não podem alarmar; garradas: têm que alarmar
    const benignos = ['calma', 'rajadas', 'ronda-vento', 'mare', 'multipath', 'poita', 'perda-sinal'];
    const garrando = ['garrando', 'garrando-lento', 'poita-rompida'];

    ({int? alarmMin, bool sawNoSignal}) run(String name, int seed, double windage) {
      final sc = scenarios[name]!;
      final mooring = sc.mooring;
      final boat = SimulatedBoat(
        scenario: name, seed: seed,
        rodeLength: mooring ? 12 : 40, depth: 6, boatLength: 8, antennaToBow: 4, windage: windage,
      );
      final watch = AnchorWatch(AnchorConfig(
        boatLength: 8, antennaToBow: 4, rodeLength: mooring ? 12 : 40, depth: 6,
        alarmRadius: mooring ? 22 : null,
      ));
      GpsFix? f;
      for (var i = 0; i < 120; i++) {
        f = boat.step(1).fix;
      }
      watch.setAnchor(boat.truthAnchorLatLon(), 'marcado');
      watch.arm();
      watch.armedAt = f!.t;
      int? alarmMin;
      bool sawNoSignal = false;
      for (var i = 0; i < 90 * 60; i++) {
        f = boat.step(1).fix;
        final s = watch.feed(f);
        final min = (f.t - watch.armedAt!) / 60000;
        if (s.state == AnchorState.nosignal) sawNoSignal = true;
        if (s.state == AnchorState.alarm && alarmMin == null) alarmMin = min.round();
      }
      return (alarmMin: alarmMin, sawNoSignal: sawNoSignal);
    }

    for (final name in benignos) {
      test('$name — sem falso alarme (2 sementes x 2 barcos)', () {
        for (final w in [1.0, 1.4]) {
          for (final seed in [1000, 1481]) {
            final r = run(name, seed, w);
            expect(r.alarmMin, isNull,
                reason: 'FALSO ALARME em $name (semente $seed, windage $w) aos ${r.alarmMin} min');
          }
        }
        if (name == 'perda-sinal') {
          expect(run(name, 1000, 1.0).sawNoSignal, isTrue, reason: 'deveria sinalizar perda de GPS');
        }
      });
    }

    for (final name in garrando) {
      test('$name — alarme dispara (2 sementes x 2 barcos)', () {
        for (final w in [1.0, 1.4]) {
          for (final seed in [1000, 1481]) {
            final r = run(name, seed, w);
            expect(r.alarmMin, isNotNull,
                reason: 'NÃO alarmou em $name (semente $seed, windage $w)');
          }
        }
      });
    }
  });
}

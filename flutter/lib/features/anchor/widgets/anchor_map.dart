/// Mapa da âncora — CustomPainter que espelha o SVG do protótipo web:
/// círculo de raio (tracejado, cor pelo estado), rastro breadcrumb, linha da
/// amarra, seta de deriva, pino da âncora, barco orientado pela proa, e o
/// "fantasma" da âncora real da simulação (para conferência visual).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/anchor_core.dart';
import '../core/geo.dart';
import '../services/anchor_controller.dart';
import '../../../theme.dart';

class AnchorMap extends StatelessWidget {
  final AnchorController c;
  final double viewSpan; // metros de largura do mapa (zoom)
  const AnchorMap({super.key, required this.c, required this.viewSpan});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(painter: _MapPainter(c, viewSpan)),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final AnchorController c;
  final double viewSpan;
  _MapPainter(this.c, this.viewSpan);

  @override
  void paint(Canvas canvas, Size size) {
    final snap = c.snapshot;
    canvas.drawRect(Offset.zero & size, Paint()..color = SB.water);

    // grade sutil
    final grid = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    for (var i = 1; i < 8; i++) {
      final x = i * size.width / 8, y = i * size.height / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (snap == null) return;

    final center = snap.anchor ?? snap.position ?? (c.lastFix?.geo);
    if (center == null) return;
    final mpp = viewSpan / size.width;
    Offset project(Geo ll) {
      final l = toLocal(center, ll);
      return Offset(size.width / 2 + l.x / mpp, size.height / 2 - l.y / mpp);
    }

    if (snap.anchor != null) {
      final a = project(snap.anchor!);
      final rPx = snap.radius / mpp;
      final ringColor = switch (snap.state) {
        AnchorState.alarm => SB.red,
        AnchorState.prealarm => SB.amber,
        _ => SB.green,
      };

      // preenchimento leve do círculo
      canvas.drawCircle(a, rPx, Paint()..color = ringColor.withOpacity(0.07));
      // círculo de raio tracejado
      _dashedCircle(canvas, a, rPx, Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5, dash: 7, gap: 7);
      // anel de pré-alarme (85%)
      _dashedCircle(canvas, a, rPx * 0.85, Paint()
        ..color = Colors.white.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1, dash: 3, gap: 6);

      // rastro breadcrumb
      final track = c.watch.trackLatLon(500);
      if (track.length > 1) {
        final path = Path();
        for (var i = 0; i < track.length; i++) {
          final q = project(track[i]);
          i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
        }
        canvas.drawPath(path, Paint()
          ..color = const Color(0xFFBFE0FF).withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round);
        final recent = track.length > 40 ? track.sublist(track.length - 40) : track;
        for (var i = 0; i < recent.length; i++) {
          final q = project(recent[i]);
          canvas.drawCircle(q, 1.6, Paint()..color = const Color(0xFFEAF4FF).withOpacity(0.15 + 0.75 * i / recent.length));
        }
      }

      // linha da amarra âncora→barco
      if (snap.position != null) {
        _dashedLine(canvas, a, project(snap.position!), Paint()
          ..color = Colors.white.withOpacity(0.35)
          ..strokeWidth = 1.5, dash: 2, gap: 4);
      }

      // seta de deriva do centro (quando garrando)
      if (snap.drift.significant && snap.drift.accumulated > 3) {
        final len = math.min(rPx * 0.9, snap.drift.accumulated / mpp * 3);
        final dr = snap.drift.bearing * d2r;
        final e = Offset(a.dx + math.sin(dr) * len, a.dy - math.cos(dr) * len);
        canvas.drawLine(a, e, Paint()
          ..color = SB.red
          ..strokeWidth = 2.5);
        canvas.drawCircle(e, 4, Paint()..color = SB.red);
      }

      _anchorPin(canvas, a);

      // fantasma da âncora real (só na simulação)
      final truth = c.truthAnchor;
      if (truth != null) {
        final ta = project(truth);
        if ((ta - a).distance > 3) {
          _dashedCircle(canvas, ta, 5, Paint()
            ..color = Colors.white.withOpacity(0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5, dash: 2, gap: 3);
          _label(canvas, ta + const Offset(8, -2), 'âncora real', Colors.white.withOpacity(0.5));
        }
      }
    }

    // barco
    final bp = snap.position ?? c.lastFix?.geo;
    if (bp != null) {
      _boat(canvas, project(bp), (c.lastFix?.heading ?? 0), snap.state);
    }
  }

  void _dashedCircle(Canvas canvas, Offset c0, double r, Paint p, {required double dash, required double gap}) {
    if (r <= 0) return;
    final circ = 2 * math.pi * r;
    final steps = (circ / (dash + gap)).floor().clamp(8, 400);
    final da = 2 * math.pi / steps;
    final frac = dash / (dash + gap);
    for (var i = 0; i < steps; i++) {
      final a0 = i * da, a1 = a0 + da * frac;
      canvas.drawArc(Rect.fromCircle(center: c0, radius: r), a0, a1 - a0, false, p);
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint p, {required double dash, required double gap}) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final s = a + dir * d;
      final e = a + dir * math.min(d + dash, total);
      canvas.drawLine(s, e, p);
      d += dash + gap;
    }
  }

  void _anchorPin(Canvas canvas, Offset a) {
    canvas.drawCircle(a, 13, Paint()..color = SB.bg);
    canvas.drawCircle(a, 13, Paint()
      ..color = SB.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    // glifo de âncora simplificado
    final p = Paint()
      ..color = SB.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a + const Offset(0, -6), a + const Offset(0, 6), p);
    canvas.drawCircle(a + const Offset(0, -6), 2, p);
    final arc = Rect.fromCircle(center: a + const Offset(0, 2), radius: 6);
    canvas.drawArc(arc, math.pi * 0.15, math.pi * 0.7, false, p);
    canvas.drawLine(a + const Offset(-6, 2), a + const Offset(-6, 5), p);
    canvas.drawLine(a + const Offset(6, 2), a + const Offset(6, 5), p);
  }

  void _boat(Canvas canvas, Offset o, double heading, AnchorState state) {
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.rotate(heading * d2r);
    final hull = Path()
      ..moveTo(0, -15)
      ..cubicTo(6, -9, 7, 6, 4, 14)
      ..lineTo(-4, 14)
      ..cubicTo(-7, 6, -6, -9, 0, -15)
      ..close();
    canvas.drawPath(hull, Paint()..color = state == AnchorState.alarm ? SB.red : Colors.white);
    canvas.drawPath(hull, Paint()
      ..color = SB.bg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    canvas.drawCircle(const Offset(0, -2), 2.4, Paint()..color = SB.bg);
    canvas.restore();
  }

  void _label(Canvas canvas, Offset o, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 9)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}

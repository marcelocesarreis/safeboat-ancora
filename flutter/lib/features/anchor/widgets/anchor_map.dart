/// Mapa da âncora — CustomPainter que espelha o SVG do protótipo web, agora com
/// ARRASTE da âncora: no modo edição você move o pino até o ponto real no fundo
/// e vê a distância linear até o barco em tempo real. Toque no pino mostra a
/// distância. Espelha public/app.js.
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

  // projeção Geo -> pixel e inversa, dado o tamanho do canvas
  Geo _center(Size size) {
    final snap = c.snapshot;
    return c.dragCenter ??
        snap?.anchor ??
        snap?.position ??
        c.lastFix?.geo ??
        const Geo(-27.5954, -48.5480);
  }

  Offset _project(Geo ll, Geo center, double mpp, Size s) {
    final l = toLocal(center, ll);
    return Offset(s.width / 2 + l.x / mpp, s.height / 2 - l.y / mpp);
  }

  Geo _unproject(Offset px, Geo center, double mpp, Size s) {
    final local = Vec((px.dx - s.width / 2) * mpp, (s.height / 2 - px.dy) * mpp);
    return fromLocal(center, local);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          final mpp = viewSpan / size.width;
          final center = _center(size);

          bool hitAnchor(Offset local) {
            final anchor = c.watch.anchor;
            if (anchor == null) return false;
            final a = _project(anchor, center, mpp, size);
            return (local - a).distance < 34;
          }

          return GestureDetector(
            onTapUp: (d) {
              if (hitAnchor(d.localPosition)) c.tapAnchor();
            },
            onPanStart: c.editMode
                ? (d) {
                    if (hitAnchor(d.localPosition)) {
                      c.moveAnchor(_unproject(d.localPosition, center, mpp, size));
                    }
                  }
                : null,
            onPanUpdate: c.editMode
                ? (d) => c.moveAnchor(_unproject(d.localPosition, center, mpp, size))
                : null,
            child: CustomPaint(
              size: size,
              painter: _MapPainter(c, viewSpan, center, mpp),
            ),
          );
        }),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final AnchorController c;
  final double viewSpan;
  final Geo center;
  final double mpp;
  _MapPainter(this.c, this.viewSpan, this.center, this.mpp);

  Offset _p(Geo ll, Size s) {
    final l = toLocal(center, ll);
    return Offset(s.width / 2 + l.x / mpp, s.height / 2 - l.y / mpp);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final snap = c.snapshot;
    canvas.drawRect(Offset.zero & size, Paint()..color = SB.water);

    final grid = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    for (var i = 1; i < 8; i++) {
      final x = i * size.width / 8, y = i * size.height / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (snap == null) return;

    if (snap.anchor != null) {
      final a = _p(snap.anchor!, size);
      final rPx = snap.radius / mpp;
      final ringColor = switch (snap.state) {
        AnchorState.alarm => SB.red,
        AnchorState.prealarm => SB.amber,
        _ => SB.green,
      };

      canvas.drawCircle(a, rPx, Paint()..color = ringColor.withOpacity(0.07));
      _dashedCircle(canvas, a, rPx, Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5, dash: 7, gap: 7);
      _dashedCircle(canvas, a, rPx * 0.85, Paint()
        ..color = Colors.white.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1, dash: 3, gap: 6);

      // rastro breadcrumb
      final track = c.watch.trackLatLon(500);
      if (track.length > 1) {
        final path = Path();
        for (var i = 0; i < track.length; i++) {
          final q = _p(track[i], size);
          i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
        }
        canvas.drawPath(path, Paint()
          ..color = const Color(0xFFBFE0FF).withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round);
        final recent = track.length > 40 ? track.sublist(track.length - 40) : track;
        for (var i = 0; i < recent.length; i++) {
          final q = _p(recent[i], size);
          canvas.drawCircle(q, 1.6, Paint()..color = const Color(0xFFEAF4FF).withOpacity(0.15 + 0.75 * i / recent.length));
        }
      }

      // linha da amarra âncora→barco
      if (snap.position != null) {
        _dashedLine(canvas, a, _p(snap.position!, size), Paint()
          ..color = Colors.white.withOpacity(0.35)
          ..strokeWidth = 1.5, dash: 2, gap: 4);
      }

      // seta de deriva do centro
      if (snap.drift.significant && snap.drift.accumulated > 3) {
        final len = math.min(rPx * 0.9, snap.drift.accumulated / mpp * 3);
        final dr = snap.drift.bearing * d2r;
        final e = Offset(a.dx + math.sin(dr) * len, a.dy - math.cos(dr) * len);
        canvas.drawLine(a, e, Paint()
          ..color = SB.red
          ..strokeWidth = 2.5);
        canvas.drawCircle(e, 4, Paint()..color = SB.red);
      }

      // realce do pino durante a edição
      if (c.editMode) {
        _dashedCircle(canvas, a, 26, Paint()
          ..color = SB.green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5, dash: 3, gap: 3);
        canvas.drawCircle(a, 26, Paint()..color = SB.green.withOpacity(0.15));
      }

      _anchorPin(canvas, a);

      // balão de distância âncora→barco (na edição ou ao tocar)
      if ((c.editMode || c.showAnchorDist) && snap.position != null) {
        final b = _p(snap.position!, size);
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        _distanceLabel(canvas, mid, '${snap.distance.round()} m');
      }

      // fantasma da âncora real (só na simulação)
      final truth = c.truthAnchor;
      if (truth != null) {
        final ta = _p(truth, size);
        if ((ta - a).distance > 3) {
          _dashedCircle(canvas, ta, 5, Paint()
            ..color = Colors.white.withOpacity(0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5, dash: 2, gap: 3);
          _label(canvas, ta + const Offset(8, -2), 'âncora real', Colors.white.withOpacity(0.5));
        }
      }
    }

    final bp = snap.position ?? c.lastFix?.geo;
    if (bp != null) {
      _boat(canvas, _p(bp, size), (c.lastFix?.heading ?? 0), snap.state);
    }
  }

  void _dashedCircle(Canvas canvas, Offset c0, double r, Paint p, {required double dash, required double gap}) {
    if (r <= 0) return;
    final steps = (2 * math.pi * r / (dash + gap)).floor().clamp(8, 400);
    final da = 2 * math.pi / steps;
    final frac = dash / (dash + gap);
    for (var i = 0; i < steps; i++) {
      canvas.drawArc(Rect.fromCircle(center: c0, radius: r), i * da, da * frac, false, p);
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint p, {required double dash, required double gap}) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), p);
      d += dash + gap;
    }
  }

  void _distanceLabel(Canvas canvas, Offset o, String text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + 16, h = 22.0;
    final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: w, height: h), const Radius.circular(11));
    canvas.drawRRect(rect, Paint()..color = SB.bg.withOpacity(0.85));
    canvas.drawRRect(rect, Paint()
      ..color = SB.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
  }

  void _anchorPin(Canvas canvas, Offset a) {
    canvas.drawCircle(a, 13, Paint()..color = SB.bg);
    canvas.drawCircle(a, 13, Paint()
      ..color = SB.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
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

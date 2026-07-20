/// Bottom sheet "Configurar raio do alarme" — espelha o sheet do protótipo web.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/geo.dart';
import '../services/anchor_controller.dart';
import '../../../theme.dart';

/// Abre o sheet; ao confirmar, lança a âncora e ativa a verificação de aguante.
Future<void> showRadiusSheet(BuildContext context, AnchorController c) {
  c.pendingRadius = null;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF243A63),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _RadiusSheet(c: c),
  );
}

class _RadiusSheet extends StatefulWidget {
  final AnchorController c;
  const _RadiusSheet({required this.c});
  @override
  State<_RadiusSheet> createState() => _RadiusSheetState();
}

class _RadiusSheetState extends State<_RadiusSheet> {
  late final TextEditingController _rode;
  late final TextEditingController _depth;
  late final TextEditingController _boat;
  late final TextEditingController _margin;

  AnchorController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _rode = TextEditingController(text: c.cfg.rodeLength.toStringAsFixed(0));
    _depth = TextEditingController(text: c.cfg.depth.toStringAsFixed(0));
    _boat = TextEditingController(text: c.cfg.boatLength.toStringAsFixed(0));
    _margin = TextEditingController(text: c.cfg.gpsMargin.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _rode.dispose();
    _depth.dispose();
    _boat.dispose();
    _margin.dispose();
    super.dispose();
  }

  void _readInputs() {
    c.updateConfig(
      rode: double.tryParse(_rode.text) ?? c.cfg.rodeLength,
      depth: double.tryParse(_depth.text) ?? c.cfg.depth,
      boat: double.tryParse(_boat.text) ?? c.cfg.boatLength,
      margin: double.tryParse(_margin.text) ?? c.cfg.gpsMargin,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final r = c.effectiveRadius;
    final scope = c.cfg.scope;
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 46, height: 5,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.3), borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Configurar raio do alarme', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 11,
                child: CustomPaint(painter: _MiniMapPainter(radius: r, cfg: c.cfg)),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              _field('Amarra lançada', _rode, 'm'),
              const SizedBox(width: 10),
              _field('Profundidade', _depth, 'm'),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _field('Comp. do barco', _boat, 'm'),
              const SizedBox(width: 10),
              _field('Folga GPS', _margin, 'm'),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: SB.card3, borderRadius: BorderRadius.circular(11)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ℹ️  '),
                Expanded(
                  child: Text.rich(TextSpan(
                    style: const TextStyle(fontSize: 12, color: SB.muted, height: 1.5),
                    children: [
                      const TextSpan(text: 'Relação de fundeio (scope) '),
                      TextSpan(text: '${scope.toStringAsFixed(1).replaceAll('.', ',')}:1', style: const TextStyle(color: SB.green, fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' — recomendado 5:1 a 7:1. O raio já soma o alcance da amarra, o comprimento do barco e a folga de GPS.'),
                    ],
                  )),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Raio do alarme', style: TextStyle(fontSize: 14, color: Color(0xFFC7D0E4))),
              Text('${r.round()} m', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: SB.green,
                inactiveTrackColor: SB.card3,
                thumbColor: SB.green,
                overlayColor: SB.greenSoft,
              ),
              child: Slider(
                min: 15, max: 120, value: r.clamp(15, 120).toDouble(),
                onChanged: (v) => setState(() => c.setPendingRadius(v)),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: SB.green, foregroundColor: SB.bg,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  _readInputs();
                  c.pendingRadius = double.tryParse(r.toStringAsFixed(0));
                  c.confirmArm();
                  Navigator.pop(context);
                },
                child: const Text('Confirmar e ativar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctl, String unit) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: SB.card3, borderRadius: BorderRadius.circular(11)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10.5, color: SB.muted, fontWeight: FontWeight.w600, letterSpacing: .3)),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Expanded(
              child: TextField(
                controller: ctl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
                onChanged: (_) => _readInputs(),
              ),
            ),
            Text(unit, style: const TextStyle(fontSize: 12, color: SB.muted, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  final double radius;
  final dynamic cfg;
  _MiniMapPainter({required this.radius, required this.cfg});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = SB.water);
    final cx = size.width / 2, cy = size.height / 2;
    final physical = swingRadius(rodeLength: cfg.rodeLength, depth: cfg.depth, bowRoller: cfg.bowRoller, boatLength: cfg.boatLength, gpsMargin: 0);
    final scale = (size.height * 0.42) / math.max(radius, math.max(physical, 20));
    final rPx = radius * scale;
    final ringPaint = Paint()
      ..color = SB.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(Offset(cx, cy), rPx, Paint()..color = SB.green.withOpacity(0.10));
    _dashedCircle(canvas, Offset(cx, cy), rPx, ringPaint, dash: 7, gap: 7);
    final phPx = physical * scale;
    if (phPx < rPx) {
      _dashedCircle(canvas, Offset(cx, cy), phPx, Paint()
        ..color = Colors.white.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1, dash: 3, gap: 5);
    }
    // barco no topo do círculo
    canvas.drawCircle(Offset(cx, cy - rPx * 0.7), 5, Paint()..color = Colors.white);
    // pino da âncora no centro
    canvas.drawCircle(Offset(cx, cy), 8, Paint()..color = SB.bg);
    canvas.drawCircle(Offset(cx, cy), 8, Paint()
      ..color = SB.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    final tp = TextPainter(
      text: TextSpan(text: 'raio ${radius.round()} m', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy + rPx + 6));
  }

  void _dashedCircle(Canvas canvas, Offset c0, double r, Paint p, {required double dash, required double gap}) {
    if (r <= 0) return;
    final steps = (2 * math.pi * r / (dash + gap)).floor().clamp(8, 300);
    final da = 2 * math.pi / steps;
    final frac = dash / (dash + gap);
    for (var i = 0; i < steps; i++) {
      canvas.drawArc(Rect.fromCircle(center: c0, radius: r), i * da, da * frac, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter old) => old.radius != radius;
}

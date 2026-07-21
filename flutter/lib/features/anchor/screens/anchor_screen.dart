/// SAFEBOAT — Tela da Âncora Virtual. Espelha o protótipo web:
/// barra de status, cabeçalho, simulador de cenários, estado do alarme, mapa ao
/// vivo, métricas, ações, integração com os dados do SAFEBOAT e histórico.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/anchor_core.dart';
import '../core/sim_device.dart';
import '../services/anchor_controller.dart';
import '../widgets/anchor_map.dart';
import '../widgets/radius_sheet.dart';
import '../../../theme.dart';

enum _CondLvl { ok, warn, danger }

class AnchorScreen extends StatefulWidget {
  const AnchorScreen({super.key});
  @override
  State<AnchorScreen> createState() => _AnchorScreenState();
}

class _AnchorScreenState extends State<AnchorScreen> {
  final AnchorController c = AnchorController();
  double viewSpan = 140; // zoom do mapa (metros)

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SB.bg,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final snap = c.snapshot;
            return Stack(children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                children: [
                  _statusBar(),
                  _header(),
                  const SizedBox(height: 6),
                  _simBar(),
                  const SizedBox(height: 10),
                  _alarmState(snap),
                  const SizedBox(height: 4),
                  _mapSection(snap),
                  if (snap != null && snap.state == AnchorState.alarm) ...[
                    const SizedBox(height: 14),
                    _emergencyPanel(snap),
                  ],
                  const SizedBox(height: 12),
                  _metrics(snap),
                  const SizedBox(height: 4),
                  _actions(snap),
                  // integração com os demais dados do SAFEBOAT (só com âncora ativa)
                  if (snap != null && snap.anchor != null && snap.state != AnchorState.idle) ...[
                    const SizedBox(height: 18),
                    _onboardSection(snap),
                    const SizedBox(height: 18),
                    _cameraSection(snap),
                  ],
                  const SizedBox(height: 18),
                  _eventsHeader(),
                  _events(),
                ],
              ),
              if (snap != null && snap.state == AnchorState.alarm) _alarmBanner(snap),
              _bottomNav(),
            ]);
          },
        ),
      ),
    );
  }

  // ---------- barra de status ----------
  Widget _statusBar() {
    final t = c.lastFix != null ? DateTime.fromMillisecondsSinceEpoch(c.lastFix!.t) : DateTime.now();
    final hh = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(hh, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const Row(children: [Text('▪▪▪ ', style: TextStyle(fontSize: 12)), Icon(Icons.wifi, size: 15), SizedBox(width: 6), Icon(Icons.battery_5_bar, size: 16)]),
      ]),
    );
  }

  // ---------- cabeçalho ----------
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Container(
          width: 58, height: 58,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const Text('🛥️', style: TextStyle(fontSize: 26)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('MAGNA 260', style: TextStyle(fontSize: 12, color: SB.muted, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
            Text('RÔ', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: .5, height: 1.1)),
          ]),
        ),
        Container(width: 40, height: 40, decoration: const BoxDecoration(color: SB.card3, shape: BoxShape.circle), alignment: Alignment.center, child: const Text('L', style: TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(width: 12),
        Stack(clipBehavior: Clip.none, children: [
          const Icon(Icons.notifications_none, size: 24),
          Positioned(top: -6, right: -8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: SB.amber, borderRadius: BorderRadius.circular(9)), child: const Text('9+', style: TextStyle(color: SB.bg, fontSize: 10, fontWeight: FontWeight.w700)))),
        ]),
      ]),
    );
  }

  // ---------- simulador ----------
  Widget _simBar() {
    const danger = {'garrando', 'garrando-lento', 'poita-rompida'};
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2B2150), Color(0xFF1F2B4D)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SB.green.withOpacity(0.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: SB.green, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          const Text('SIMULADOR DE DISPOSITIVO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: SB.green)),
          const Spacer(),
          Text('t+${c.simElapsedMin} min', style: const TextStyle(fontSize: 11, color: SB.muted, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final s in scenarios.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _scenChip(s, danger.contains(s.key)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 34,
          child: Text(c.scenarioDef.desc, style: const TextStyle(fontSize: 11.5, color: SB.muted, height: 1.45)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _simBtn(c.playing ? '⏸ Pausar' : '▶ Continuar', c.togglePlay, primary: true)),
          const SizedBox(width: 8),
          Expanded(child: _simBtn('↺ Reiniciar', c.restart)),
          const SizedBox(width: 8),
          for (final s in [30.0, 60.0, 120.0])
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: _spdBtn(s),
            ),
        ]),
      ]),
    );
  }

  Widget _scenChip(Scenario s, bool danger) {
    final active = s.key == c.scenario;
    final bg = active ? (danger ? SB.red : SB.green) : SB.card3;
    final fg = active ? (danger ? Colors.white : SB.bg) : const Color(0xFFC7D0E4);
    return GestureDetector(
      onTap: () => c.selectScenario(s.key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9), border: Border.all(color: active ? bg : Colors.white.withOpacity(0.12))),
        alignment: Alignment.center,
        child: Text(s.nome, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ),
    );
  }

  Widget _simBtn(String label, VoidCallback onTap, {bool primary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: primary ? SB.greenSoft : SB.card3, borderRadius: BorderRadius.circular(9)),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primary ? SB.green : Colors.white)),
      ),
    );
  }

  Widget _spdBtn(double s) {
    final on = c.speed == s;
    return GestureDetector(
      onTap: () => c.setSpeed(s),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(color: on ? SB.green : SB.card3, borderRadius: BorderRadius.circular(9)),
        child: Text('${s.round()}×', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? SB.bg : Colors.white)),
      ),
    );
  }

  // ---------- estado do alarme ----------
  Widget _alarmState(AnchorSnapshot? snap) {
    final st = snap?.state ?? AnchorState.idle;
    final (iconBg, sub, main) = switch (st) {
      AnchorState.idle => (const Color(0xFF39456A), 'Âncora não lançada', 'Alarme de âncora inativo'),
      AnchorState.setting => (const Color(0xFF39456A), 'Verificando aguante', 'Cravando a âncora…'),
      AnchorState.armed => (SB.green, 'Dentro do raio de ${snap!.radius.round()} m', 'Alarme de âncora Ativo'),
      AnchorState.prealarm => (SB.amber, 'Atenção', 'Encostando no limite'),
      AnchorState.alarm => (SB.red, 'EMERGÊNCIA', 'GARRANDO — barco à deriva'),
      AnchorState.nosignal => (const Color(0xFF6B7699), 'Sinal de GPS ruim', 'Vigília em dúvida'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
          child: Icon(st == AnchorState.alarm ? Icons.warning_amber_rounded : Icons.anchor, color: SB.bg, size: 27),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sub, style: const TextStyle(fontSize: 13, color: Color(0xFFC7D0E4))),
            Text(main, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.15)),
          ]),
        ),
      ]),
    );
  }

  // ---------- mapa ----------
  Widget _mapSection(AnchorSnapshot? snap) {
    final acc = c.lastFix?.accuracy ?? 0;
    final gpsColor = acc > 25 ? SB.red : acc > 12 ? SB.amber : SB.green;
    return Column(children: [
      Stack(children: [
        Container(
          decoration: c.editMode
              ? BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: SB.green, width: 2))
              : null,
          child: AnchorMap(c: c, viewSpan: viewSpan),
        ),
        Positioned(
          top: 10, left: 10, right: 10,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _mapBadge('dist.', snap?.anchor != null ? '${snap!.distance.round()} m' : '—', Colors.white),
            _mapBadge('GPS', '±${acc.round()} m', gpsColor),
          ]),
        ),
        if (!c.editMode)
          Positioned(
            bottom: 10, right: 10,
            child: Column(children: [
              _zoomBtn('+', () => setState(() => viewSpan = (viewSpan / 1.3).clamp(50, 600))),
              const SizedBox(height: 6),
              _zoomBtn('−', () => setState(() => viewSpan = (viewSpan * 1.3).clamp(50, 600))),
            ]),
          ),
        // barra de edição da âncora
        if (c.editMode && snap != null)
          Positioned(
            left: 10, right: 10, bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: SB.bg.withOpacity(0.86), borderRadius: BorderRadius.circular(12), border: Border.all(color: SB.greenSoft)),
              child: Row(children: [
                Expanded(
                  child: Text.rich(TextSpan(
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.3),
                    children: [
                      const TextSpan(text: 'Arraste a âncora até o ponto real. '),
                      TextSpan(text: 'Distância até o barco: ${snap.distance.round()} m', style: const TextStyle(color: SB.green)),
                    ],
                  )),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: c.finishEdit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: SB.green, borderRadius: BorderRadius.circular(9)),
                    child: const Text('Concluir', style: TextStyle(color: SB.bg, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ),
              ]),
            ),
          ),
      ]),
      if (c.canEdit)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: GestureDetector(
            onTap: c.startEdit,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SB.green.withOpacity(0.55), width: 1.5, style: BorderStyle.solid),
              ),
              alignment: Alignment.center,
              child: const Text('✎ Editar posição da âncora', style: TextStyle(color: SB.green, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
    ]);
  }

  Widget _mapBadge(String k, String v, Color vColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: SB.bg.withOpacity(0.74), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$k ', style: const TextStyle(fontSize: 11, color: SB.muted)),
        Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: vColor)),
      ]),
    );
  }

  Widget _zoomBtn(String s, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: SB.bg.withOpacity(0.8), borderRadius: BorderRadius.circular(9)),
        alignment: Alignment.center,
        child: Text(s, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ---------- métricas ----------
  Widget _metrics(AnchorSnapshot? snap) {
    if (snap == null || snap.anchor == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: SB.card, borderRadius: BorderRadius.circular(13)),
        alignment: Alignment.center,
        child: const Text('Lance a âncora e ative o alarme para começar a vigília.', style: TextStyle(color: SB.muted, fontSize: 13), textAlign: TextAlign.center),
      );
    }
    final drift = snap.drift;
    final driftTxt = drift.significant ? '${drift.rate.toStringAsFixed(2)} m/min' : 'estável';
    final gaugeColor = snap.usage > 1 ? SB.red : snap.usage > 0.85 ? SB.amber : SB.green;
    return Column(children: [
      Row(children: [
        _metric('Distância', '${snap.distance.round()}', 'm'),
        const SizedBox(width: 9),
        _metric('Raio', '${snap.radius.round()}', 'm'),
        const SizedBox(width: 9),
        _metric('Rumo p/ âncora', '${((snap.bearing + 180) % 360).round()}', '°'),
      ]),
      const SizedBox(height: 9),
      Row(children: [
        _metric('Scope', snap.scope.toStringAsFixed(1), ':1'),
        const SizedBox(width: 9),
        _metric('Prof.', snap.depth?.toStringAsFixed(1) ?? '—', 'm'),
        const SizedBox(width: 9),
        _metric('Deriva centro', driftTxt, '', valueColor: drift.significant ? const Color(0xFFFF8F88) : null),
      ]),
      const SizedBox(height: 9),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: SB.card, borderRadius: BorderRadius.circular(13)),
        child: Row(children: [
          const Text('USO DO RAIO', style: TextStyle(fontSize: 11, color: SB.muted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(
            child: Stack(children: [
              Container(height: 8, decoration: BoxDecoration(color: SB.card3, borderRadius: BorderRadius.circular(6))),
              FractionallySizedBox(
                widthFactor: snap.usage.clamp(0, 1).toDouble(),
                child: Container(height: 8, decoration: BoxDecoration(color: gaugeColor, borderRadius: BorderRadius.circular(6))),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Text('${(snap.usage * 100).round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    ]);
  }

  Widget _metric(String k, String v, String unit, {Color? valueColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(color: SB.card, borderRadius: BorderRadius.circular(13)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k.toUpperCase(), style: const TextStyle(fontSize: 10, color: SB.muted, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text.rich(TextSpan(
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: valueColor ?? Colors.white),
            children: [TextSpan(text: v), TextSpan(text: unit.isEmpty ? '' : ' $unit', style: const TextStyle(fontSize: 12, color: SB.muted, fontWeight: FontWeight.w600))],
          ), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  // ---------- ações ----------
  Widget _actions(AnchorSnapshot? snap) {
    final st = snap?.state ?? AnchorState.idle;
    if (st == AnchorState.idle && !c.armed) {
      return _pill('⚓  ATIVAR ALARME', () => showRadiusSheet(context, c), solid: true);
    }
    if (st == AnchorState.setting) {
      return Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: SB.card3, borderRadius: BorderRadius.circular(11)),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('📍  '),
            Expanded(child: Text('Arraste a âncora no mapa até onde ela caiu no fundo. Toque nela para ver a distância até o barco. Depois, ative a vigília.', style: TextStyle(fontSize: 12, color: SB.muted, height: 1.4))),
          ]),
        ),
        const SizedBox(height: 10),
        _pill('Ativar vigília', c.finishSetting, green: true),
      ]);
    }
    if (st == AnchorState.alarm || st == AnchorState.prealarm) {
      return Row(children: [
        Expanded(child: _pill('Reconhecer', c.acknowledge)),
        const SizedBox(width: 10),
        Expanded(child: _pill('Desativar', c.disarm, ghostRed: true)),
      ]);
    }
    return _pill('🔕  DESATIVAR ALARME', c.disarm, ghostRed: true);
  }

  Widget _pill(String label, VoidCallback onTap, {bool solid = false, bool green = false, bool ghostRed = false}) {
    final Color bg, fg, border;
    if (solid) {
      bg = Colors.white; fg = SB.bg; border = Colors.white;
    } else if (green) {
      bg = SB.green; fg = SB.bg; border = SB.green;
    } else if (ghostRed) {
      bg = Colors.transparent; fg = const Color(0xFFFF8F88); border = SB.red.withOpacity(0.6);
    } else {
      bg = Colors.transparent; fg = Colors.white; border = Colors.white.withOpacity(0.4);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 1.5)),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg, letterSpacing: .5)),
      ),
    );
  }

  // ---------- eventos ----------
  Widget _eventsHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('HISTÓRICO', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: .5)),
        Text('${c.watch.events.length} eventos', style: const TextStyle(fontSize: 12, color: SB.muted)),
      ]),
    );
  }

  Widget _events() {
    final evs = c.watch.events.reversed.take(8).toList();
    if (evs.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nenhum evento ainda.', style: TextStyle(color: SB.muted, fontSize: 13)));
    }
    const icons = {'alarme': '⚠️', 'atencao': '👀', 'armado': '⚓', 'desarmado': '🔕', 'ancora': '⚓', 'normal': '✓', 'reconhecido': '👍', 'sinal': '📡'};
    const bg = {'alarme': SB.redSoft, 'atencao': SB.amberSoft, 'armado': SB.greenSoft, 'normal': SB.greenSoft};
    return Column(
      children: [
        for (final e in evs)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(color: bg[e.kind] ?? SB.card, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(icons[e.kind] ?? '•', style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 11),
              Expanded(child: Text(e.text, style: const TextStyle(fontSize: 13, height: 1.3))),
              const SizedBox(width: 8),
              Text(_hhmm(e.t), style: const TextStyle(fontSize: 11, color: SB.muted)),
            ]),
          ),
      ],
    );
  }

  String _hhmm(int t) {
    final d = DateTime.fromMillisecondsSinceEpoch(t);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  // ---------- banner de alarme ----------
  Widget _alarmBanner(AnchorSnapshot snap) {
    final ev = c.watch.events.where((e) => e.kind == 'alarme').toList();
    final msg = ev.isNotEmpty ? ev.last.text.replaceAll('GARRANDO — ', '') : 'O barco está garrando';
    return Positioned(
      top: 8, left: 16, right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: SB.red, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: SB.red.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 10))]),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), alignment: Alignment.center, child: const Text('⚠️', style: TextStyle(fontSize: 20))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ALARME DE ÂNCORA', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(msg, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9))),
              ]),
            ),
            GestureDetector(
              onTap: c.acknowledge,
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), borderRadius: BorderRadius.circular(9)), child: const Text('Reconhecer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------- integração: profundidade com "arrasto p/ raso" no garrando ----------
  ({double depth, double shoal}) _shoaledDepth(AnchorSnapshot snap) {
    final base = snap.depth ?? 6;
    final shoal = snap.state == AnchorState.alarm
        ? math.min(base * 0.55, snap.drift.accumulated * 0.06)
        : 0.0;
    return (depth: base - shoal, shoal: shoal);
  }

  String _cardinal(double deg) {
    const dirs = ['N', 'NE', 'L', 'SE', 'S', 'SO', 'O', 'NO'];
    return dirs[(((deg % 360) / 45).round()) % 8];
  }

  // ---------- integração: condições a bordo ----------
  Widget _onboardSection(AnchorSnapshot snap) {
    final windKn = c.windKnots.round();
    final windDir = _cardinal(c.windDir);
    final windWarn = windKn >= 25;
    final sd = _shoaledDepth(snap);
    final depthDanger = sd.shoal > 0.4;
    final vazante = c.tideVazante;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHead('A BORDO', snap.state == AnchorState.alarm ? 'verifique antes de agir' : 'durante o fundeio'),
      Wrap(spacing: 9, runSpacing: 9, children: [
        _cond('🌊', 'Profundidade', sd.depth.toStringAsFixed(1).replaceAll('.', ','), 'm', depthDanger ? '▼ diminuindo' : '● estável', depthDanger ? _CondLvl.danger : _CondLvl.ok),
        _cond('💨', 'Vento', '$windKn', 'nós', '${windWarn ? '▲' : '●'} $windDir', windWarn ? _CondLvl.warn : _CondLvl.ok),
        _cond('🌙', 'Maré', vazante ? 'Vazante' : 'Estável', '', vazante ? '▼ baixando' : '● scope ok', _CondLvl.ok),
        _cond('🔋', 'Baterias', '12,8', 'V', '● guincho ok', _CondLvl.ok),
        _cond('💧', 'Porão', 'Seco', '', '● bomba ok', _CondLvl.ok),
      ]),
    ]);
  }

  Widget _cond(String icon, String label, String val, String unit, String sub, _CondLvl lvl) {
    final (bg, subColor, border) = switch (lvl) {
      _CondLvl.danger => (SB.red.withOpacity(0.12), const Color(0xFFFF8F88), SB.red.withOpacity(0.45)),
      _CondLvl.warn => (SB.amber.withOpacity(0.10), SB.amber, SB.amber.withOpacity(0.35)),
      _CondLvl.ok => (SB.card, SB.green, Colors.transparent),
    };
    return Container(
      width: (MediaQuery.of(context).size.width.clamp(0.0, 430.0) - 58) / 3,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13), border: Border.all(color: border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 22, height: 22, decoration: BoxDecoration(color: SB.card3, borderRadius: BorderRadius.circular(7)), alignment: Alignment.center, child: Text(icon, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 10.5, color: SB.muted, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 7),
        Text.rich(TextSpan(style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700), children: [
          TextSpan(text: val),
          if (unit.isNotEmpty) TextSpan(text: ' $unit', style: const TextStyle(fontSize: 11, color: SB.muted, fontWeight: FontWeight.w600)),
        ]), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(sub, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: subColor)),
      ]),
    );
  }

  // ---------- integração: câmera ----------
  Widget _cameraSection(AnchorSnapshot snap) {
    final alarm = snap.state == AnchorState.alarm;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHead('CÂMERAS', 'Convés · ao vivo'),
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: alarm ? [BoxShadow(color: SB.red.withOpacity(0.4), blurRadius: 30, offset: const Offset(0, 8))] : null,
          border: alarm ? Border.all(color: SB.red, width: 2) : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              CustomPaint(painter: _DeckCamPainter(alarm)),
              Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x40101A30), Colors.transparent, Color(0xCC101A30)], stops: [0, 0.5, 1]))),
              Positioned(top: 10, left: 10, child: _liveBadge()),
              if (alarm) Positioned(top: 10, right: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: SB.red, borderRadius: BorderRadius.circular(20)), child: const Text('👁 VER AGORA', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)))),
              const Positioned(left: 12, bottom: 10, child: Text('Convés', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _liveBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: SB.bg.withOpacity(0.72), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: SB.red, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          const Text('AO VIVO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ]),
      );

  // ---------- integração: painel de emergência ----------
  Widget _emergencyPanel(AnchorSnapshot snap) {
    final drift = snap.drift;
    final dir = _cardinal(drift.significant ? drift.bearing : snap.bearing);
    final dragged = math.max(drift.accumulated, math.max(0.0, snap.distance - snap.radius)).round();
    final sd = _shoaledDepth(snap);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [SB.red.withOpacity(0.16), SB.red.withOpacity(0.06)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SB.red.withOpacity(0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 9, height: 9, decoration: const BoxDecoration(color: SB.red, shape: BoxShape.circle)),
          const SizedBox(width: 9),
          const Text('GARRANDO — AJA AGORA', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('há ${snap.outsideFor}s', style: const TextStyle(fontSize: 11, color: Color(0xFFFFB0AB), fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: SizedBox(width: 112, height: 84, child: Stack(fit: StackFit.expand, children: [
              CustomPaint(painter: _DeckCamPainter(true)),
              Positioned(top: 5, left: 5, child: _liveBadge()),
            ])),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _emFact('🧭', 'Deriva ', '$dir · ${drift.rate.toStringAsFixed(1)} m/min', false),
            const SizedBox(height: 6),
            _emFact('📏', 'Já saiu ', '$dragged m do círculo', false),
            const SizedBox(height: 6),
            _emFact('🌊', 'Fundo ', '${sd.depth.toStringAsFixed(1).replaceAll('.', ',')} m e caindo', true),
          ])),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _emBtn('🔕 Silenciar', Colors.white, SB.bg, c.acknowledge)),
          const SizedBox(width: 8),
          Expanded(child: _emBtn('👁 Ver câmeras', Colors.white.withOpacity(0.14), Colors.white, () {})),
        ]),
      ]),
    );
  }

  Widget _emFact(String icon, String label, String value, bool warn) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 22, child: Text(icon, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center)),
      const SizedBox(width: 6),
      Expanded(child: Text.rich(TextSpan(
        style: TextStyle(fontSize: 12.5, height: 1.25, color: warn ? const Color(0xFFFFD0CC) : Colors.white),
        children: [TextSpan(text: label), TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700))],
      ))),
    ]);
  }

  Widget _emBtn(String label, Color bg, Color fg, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _sectionHead(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: .5)),
        Text(sub, style: const TextStyle(fontSize: 12, color: SB.muted)),
      ]),
    );
  }

  // ---------- bottom nav ----------
  Widget _bottomNav() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        padding: EdgeInsets.fromLTRB(6, 12, 6, 14 + MediaQuery.of(context).padding.bottom),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: const [
          _NavItem(icon: Icons.waves, label: 'SafeBoat', active: true),
          _NavItem(icon: Icons.navigation_outlined, label: 'Navegação'),
          _NavItem(icon: Icons.build_outlined, label: 'Revisões'),
          _NavItem(icon: Icons.chat_bubble_outline, label: 'Conversas'),
        ]),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _NavItem({required this.icon, required this.label, this.active = false});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 26, height: 26,
        decoration: BoxDecoration(color: active ? SB.bg : Colors.transparent, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: active ? Colors.white : const Color(0xFF9AA3B8)),
      ),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? SB.bg : const Color(0xFF9AA3B8))),
    ]);
  }
}

/// Cena estilizada da câmera de convés (visão noturna da proa com luz de fundeio).
class _DeckCamPainter extends CustomPainter {
  final bool alarm;
  _DeckCamPainter(this.alarm);

  @override
  void paint(Canvas canvas, Size s) {
    final sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [alarm ? const Color(0xFF2A1C2C) : const Color(0xFF12233B), const Color(0xFF0A1424)],
      ).createShader(Offset.zero & s);
    canvas.drawRect(Offset.zero & s, sky);

    final hy = s.height * 0.6;
    canvas.drawRect(Rect.fromLTWH(0, hy, s.width, s.height - hy), Paint()..color = const Color(0xFF0B1A2E));
    canvas.drawLine(Offset(0, hy), Offset(s.width, hy), Paint()..color = const Color(0xFF22405F)..strokeWidth = 1);
    // reflexo
    canvas.drawOval(Rect.fromCenter(center: Offset(s.width * 0.7, s.height * 0.8), width: s.width * 0.4, height: s.height * 0.08), Paint()..color = const Color(0xFF1A3350).withOpacity(0.5));
    // pulpito/proa
    final rail = Paint()
      ..color = const Color(0xFF2B3F5C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final path = Path()
      ..moveTo(s.width * 0.05, s.height)
      ..lineTo(s.width * 0.05, s.height * 0.72)
      ..quadraticBezierTo(s.width * 0.5, s.height * 0.57, s.width * 0.95, s.height * 0.72)
      ..lineTo(s.width * 0.95, s.height);
    canvas.drawPath(path, rail);
    canvas.drawLine(Offset(s.width * 0.05, s.height * 0.72), Offset(s.width * 0.95, s.height * 0.72), Paint()..color = const Color(0xFF2B3F5C)..strokeWidth = 2);
    // luz de fundeio
    canvas.drawCircle(Offset(s.width * 0.5, s.height * 0.5), s.width * 0.05, Paint()..color = const Color(0xFFFFE08A).withOpacity(0.22));
    canvas.drawCircle(Offset(s.width * 0.5, s.height * 0.5), s.width * 0.02, Paint()..color = const Color(0xFFFFE08A));
  }

  @override
  bool shouldRepaint(covariant _DeckCamPainter old) => old.alarm != alarm;
}

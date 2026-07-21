/// SAFEBOAT — Controlador da Âncora Virtual.
///
/// Amarra o núcleo (AnchorWatch), o dispositivo (DeviceAdapter) e a UI. Toda a
/// decisão de alarme vem do núcleo — a UI só desenha e traduz toques.
///
/// Em DEMO (padrão), dirige o SimAdapter com o núcleo local, paridade total com
/// o protótipo web. Para conectar o SAFEBOAT real, ver [connectDevice] e o
/// SafeboatAdapter — nada mais na UI muda.
library;

import 'package:flutter/foundation.dart';

import '../core/anchor_core.dart';
import '../core/device_adapter.dart';
import '../core/geo.dart';
import '../core/sim_device.dart';

class AnchorController extends ChangeNotifier {
  AnchorConfig cfg = AnchorConfig();
  late AnchorWatch watch;
  late SimAdapter _sim;

  String scenario = 'calma';
  double speed = 60;
  bool playing = true;
  bool armed = false;
  GpsFix? lastFix;
  double? pendingRadius; // raio ajustado no slider antes de confirmar

  // --- edição/arraste da âncora ---
  bool editMode = false;
  Geo? dragCenter; // centro do mapa congelado durante a edição
  bool showAnchorDist = false;

  AnchorSnapshot? snapshot;

  AnchorController() {
    watch = AnchorWatch(cfg);
    _sim = _buildSim();
    _sim.warmup(90); // ~1,5 min de rastro para o mapa nascer com movimento
    _sim.start(_onFix);
  }

  SimAdapter _buildSim() => SimAdapter(
        scenario: scenario,
        speed: speed,
        seed: 7,
        rodeLength: cfg.rodeLength,
        depth: cfg.depth,
        boatLength: cfg.boatLength,
        antennaToBow: cfg.antennaToBow,
      );

  // ---- referência da simulação (só para o "fantasma" da âncora real no mapa) ----
  Geo? get truthAnchor => _sim.boat.truthAnchorLatLon();
  int get simElapsedMin => lastFix != null ? ((lastFix!.t - _sim.boat.t0) / 60000).round() : 0;
  Scenario get scenarioDef => scenarios[scenario]!;

  // ---- laço de fix ----
  void _onFix(GpsFix fix) {
    lastFix = fix;
    snapshot = watch.feed(fix);
    notifyListeners();
  }

  // ---- simulador ----
  void selectScenario(String key) {
    scenario = key;
    armed = false;
    pendingRadius = null;
    editMode = false;
    dragCenter = null;
    showAnchorDist = false;
    cfg.alarmRadius = null; // cada cenário é um novo fundeio; raio volta ao cálculo
    _sim.setScenario(key);
    watch = AnchorWatch(cfg); // compartilha o mesmo cfg
    _sim.warmup(90);
    if (playing) _sim.start(_onFix);
    snapshot = watch.snapshot();
    notifyListeners();
  }

  void setSpeed(double s) {
    speed = s;
    _sim.stop();
    _sim.speed = s;
    if (playing) _sim.start(_onFix);
    notifyListeners();
  }

  void togglePlay() {
    playing = !playing;
    if (playing) {
      _sim.start(_onFix);
    } else {
      _sim.stop();
    }
    notifyListeners();
  }

  void restart() => selectScenario(scenario);

  // ---- ações do alarme ----
  void confirmArm() {
    // watch.cfg e este cfg são o MESMO objeto (compartilhado no construtor);
    // basta aplicar o raio escolhido e lançar a âncora.
    cfg.alarmRadius = pendingRadius;
    if (lastFix != null) watch.dropAnchor(lastFix!);
    // caso comum: já fundeado — entra direto no arraste da âncora até o ponto real
    startEdit();
    snapshot = watch.snapshot();
    notifyListeners();
  }

  void finishSetting() {
    armed = true;
    watch.arm();
    finishEdit();
    snapshot = watch.snapshot();
    notifyListeners();
  }

  void disarm() {
    watch.disarm();
    armed = false;
    finishEdit();
    snapshot = watch.snapshot();
    notifyListeners();
  }

  // ---- edição/arraste da âncora ----
  bool get canEdit =>
      watch.anchor != null &&
      !editMode &&
      (watch.state == AnchorState.armed ||
          watch.state == AnchorState.prealarm ||
          watch.state == AnchorState.alarm);

  /// Entra no modo de arrastar a âncora (congela o mapa e pausa a simulação).
  void startEdit() {
    if (watch.anchor == null) return;
    editMode = true;
    _sim.stop(); // congela o barco durante o posicionamento
    dragCenter = watch.anchor;
    notifyListeners();
  }

  void finishEdit() {
    final was = editMode;
    editMode = false;
    dragCenter = null;
    if (was && playing) _sim.start(_onFix); // retoma o mar
    notifyListeners();
  }

  /// Arrasta a âncora para [pos] (mantém rastro e quadro de referência).
  void moveAnchor(Geo pos) {
    watch.moveAnchor(pos);
    snapshot = watch.snapshot();
    notifyListeners();
  }

  void tapAnchor() {
    showAnchorDist = true;
    snapshot = watch.snapshot();
    notifyListeners();
  }

  void acknowledge() {
    watch.acknowledge();
    snapshot = watch.snapshot();
    notifyListeners();
  }

  // ---- configuração de raio ----
  double get autoRadius => cfg.radius;
  double get effectiveRadius => pendingRadius ?? cfg.radius;

  void updateConfig({double? rode, double? depth}) {
    // comprimento do barco e folga de GPS vêm da base SAFEBOAT (não editáveis)
    if (rode != null) cfg.rodeLength = rode;
    if (depth != null) cfg.depth = depth;
    pendingRadius = null; // volta ao cálculo automático
    notifyListeners();
  }

  void setPendingRadius(double v) {
    pendingRadius = v;
    notifyListeners();
  }

  // ---- SAFEBOAT real (para o dev do MAIN) ----
  /// Troca o adaptador da simulação pelo dispositivo real. A UI não muda.
  void connectDevice(DeviceAdapter device) {
    _sim.stop();
    watch = AnchorWatch(cfg);
    device.start(_onFix);
  }

  @override
  void dispose() {
    _sim.stop();
    super.dispose();
  }
}

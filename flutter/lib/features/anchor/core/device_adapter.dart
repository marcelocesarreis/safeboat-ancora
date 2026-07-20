/// SAFEBOAT — Adaptador de dispositivo (porta de device-adapter.js).
///
/// A UI e o núcleo consomem SÓ esta interface. Trocar o barco simulado pelo
/// SAFEBOAT real é trocar a implementação aqui — nada mais muda.
library;

import 'dart:async';

import 'anchor_core.dart' show GpsFix;
import 'sim_device.dart';

/// Contrato de um adaptador de dispositivo.
abstract class DeviceAdapter {
  /// Metadados do dispositivo.
  Map<String, dynamic> info();

  /// Começa a emitir fixes (chama [onFix] a cada posição).
  void start(void Function(GpsFix) onFix);

  void stop();
}

/// Dirige um [SimulatedBoat] em tempo acelerado. `speed` multiplica o relógio:
/// 60 = 1 min de mar por segundo.
class SimAdapter implements DeviceAdapter {
  final SimulatedBoat boat;
  double speed;
  final double hz;
  Timer? _timer;
  void Function(GpsFix)? _onFix;
  String scenario;

  SimAdapter({
    SimulatedBoat? boat,
    this.speed = 60,
    this.hz = 1,
    this.scenario = 'calma',
    int seed = 1234,
    double rodeLength = 40,
    double depth = 6,
    double boatLength = 8,
    double antennaToBow = 4,
    double windage = 1,
  }) : boat = boat ??
            SimulatedBoat(
              scenario: scenario,
              seed: seed,
              rodeLength: rodeLength,
              depth: depth,
              boatLength: boatLength,
              antennaToBow: antennaToBow,
              windage: windage,
            );

  @override
  Map<String, dynamic> info() => {
        'source': 'simulacao',
        'boatId': 'SIM-MAGNA260',
        'sensors': {'gps': true, 'heading': true, 'depth': true, 'wind': false},
        'scenario': scenario,
      };

  void setScenario(String name) {
    scenario = name;
    boat.scenario = name;
    boat.reset();
  }

  /// Avança N segundos de mar de uma vez (para pré-encher rastro).
  GpsFix? warmup(double seconds) {
    GpsFix? f;
    final n = (seconds * hz).round();
    for (var i = 0; i < n; i++) {
      f = boat.step(1 / hz).fix;
    }
    return f;
  }

  @override
  void start(void Function(GpsFix) onFix) {
    _onFix = onFix;
    final periodMs = (1000 / (speed * hz)).round();
    _timer = Timer.periodic(Duration(milliseconds: periodMs < 8 ? 8 : periodMs), (_) {
      _onFix?.call(boat.step(1 / hz).fix);
    });
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// ESQUELETO do dispositivo real. Pronto para o dev do MAIN conectar.
///
/// O SAFEBOAT roda o núcleo A BORDO e publica telemetria. Duas fontes (iguais
/// às câmeras): WS direto no Wi-Fi do barco, ou relay na nuvem. O barco continua
/// VIGIANDO com o app fechado — só a NOTIFICAÇÃO viaja.
class SafeboatAdapter implements DeviceAdapter {
  final String boatId;
  final String? wsUrl; // ws://<safeboat-local>/anchor  ou  wss://relay/anchor
  final String token;

  SafeboatAdapter({required this.boatId, this.wsUrl, this.token = ''});

  @override
  Map<String, dynamic> info() => {
        'source': 'safeboat',
        'boatId': boatId,
        'sensors': {'gps': true, 'heading': true, 'depth': false, 'wind': false},
      };

  @override
  void start(void Function(GpsFix) onFix) {
    // TODO(dev do MAIN): abrir o WebSocket real e mapear a telemetria do
    // dispositivo para GpsFix. Exemplo:
    //
    //   final ch = WebSocketChannel.connect(Uri.parse('$wsUrl?token=$token&boat=$boatId'));
    //   ch.stream.listen((raw) {
    //     final m = jsonDecode(raw as String) as Map;
    //     onFix(GpsFix(
    //       t: m['ts'] ?? DateTime.now().millisecondsSinceEpoch,
    //       lat: m['gps']['lat'], lon: m['gps']['lon'],
    //       accuracy: (m['gps']['acc'] ?? m['gps']['hdop'] * 5).toDouble(),
    //       heading: m['ahrs']?['heading']?.toDouble(),
    //       depth: m['sounder']?['depth']?.toDouble(),
    //       novalid: (m['gps']['fix'] ?? 1) < 1,
    //     ));
    //   });
    throw UnimplementedError(
        'SafeboatAdapter é um stub — conectar ao dispositivo real no MAIN. Use SimAdapter no protótipo.');
  }

  @override
  void stop() {}
}

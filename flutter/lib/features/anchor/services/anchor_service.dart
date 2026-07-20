import 'dart:async';
import 'dart:convert';

import '../models/anchor_models.dart';

/// De onde vem a telemetria da âncora.
enum FonteAncora {
  /// WebSocket direto com o SAFEBOAT no Wi-Fi do barco (menor latência).
  wifiDoBarco,

  /// Relay na nuvem repassando a telemetria (app em 4G / dono em terra).
  relayNuvem,
}

/// Serviço da Âncora Virtual — a costura entre o app e o SAFEBOAT.
///
/// ARQUITETURA (igual à das câmeras): o SAFEBOAT é um dispositivo FIXO A BORDO
/// que roda o núcleo de decisão 24/7. Ele NÃO depende do celular estar a bordo —
/// diferente dos apps de âncora de celular, que param de vigiar quando o dono
/// desce em terra. O app é só a tela e o controle remoto; o alarme é decidido no
/// barco e a NOTIFICAÇÃO (push) viaja para o celular mesmo com o app fechado.
///
/// Três camadas de aviso (padrão dos melhores sistemas de bordo, ver README):
///   1. buzzer/voz a bordo — o próprio SAFEBOAT;
///   2. app no barco (Wi-Fi) — este serviço;
///   3. push em terra (4G/nuvem) — via relay + FCM/APNs.
///
/// Este arquivo está pronto para o dev do MAIN plugar. Os pontos de conexão real
/// estão marcados com TODO(dev). Enquanto não há barco, use `AnchorService.demo`
/// que dirige o mesmo núcleo com o simulador (paridade total com o protótipo web).
class AnchorService {
  /// URL pública do relay SAFEBOAT (produção: wss atrás de TLS).
  static const relayBase = 'https://safeboat-relay-production.up.railway.app'; // TODO(dev): endpoint definitivo
  static const relayToken = ''; // TODO(dev): JWT do usuário logado

  final String boatId;
  AnchorService({required this.boatId});

  final _snapshots = StreamController<AnchorSnapshot>.broadcast();

  /// Fluxo de snapshots da vigília (1/s típico). A UI escuta e redesenha.
  Stream<AnchorSnapshot> get snapshots => _snapshots.stream;

  FonteAncora? _fonte;
  FonteAncora? get fonte => _fonte;

  // ---- ciclo de vida da conexão -----------------------------------------

  /// Conecta à telemetria. Decide a fonte igual às câmeras: se o celular está no
  /// Wi-Fi do barco, WS direto com o SAFEBOAT; senão, relay na nuvem.
  Future<void> connect() async {
    // TODO(dev do MAIN):
    //   final local = await _portaAberta(safeboatLocalHost, 81);   // WS do dispositivo
    //   final url = local
    //       ? 'ws://$safeboatLocalHost/anchor?boat=$boatId'
    //       : '${relayBase.replaceFirst('http', 'ws')}/anchor?boat=$boatId&token=$relayToken';
    //   _ws = WebSocketChannel.connect(Uri.parse(url));
    //   _ws.stream.listen((raw) {
    //     final j = jsonDecode(raw as String) as Map;
    //     // o SAFEBOAT pode mandar {type:'snapshot', ...} já decidido,
    //     // ou {type:'fix', ...} cru para o app animar localmente.
    //     if (j['type'] == 'snapshot') {
    //       _snapshots.add(AnchorSnapshot.fromJson(j));
    //     } else if (j['type'] == 'fix') {
    //       _snapshots.add(_local.feed(GpsFix.fromJson(j)));
    //     }
    //   });
    throw UnimplementedError(
        'Conectar ao SAFEBOAT real no MAIN. Use AnchorService.demo() no protótipo.');
  }

  // ---- comandos (viajam para o dispositivo) ------------------------------

  /// Lança a âncora: marca o ponto (posição atual projetada para a proa).
  Future<void> dropAnchor() => _command('drop');

  /// Ativa a vigília.
  Future<void> arm() => _command('arm');

  /// Desativa a vigília (âncora continua marcada).
  Future<void> disarm() => _command('disarm');

  /// Silencia o alarme mas continua vigiando.
  Future<void> acknowledge() => _command('ack');

  /// Ajusta a posição da âncora (usuário arrastou o pino no mapa).
  Future<void> moveAnchor(LatLng pos) => _command('setAnchor', {'lat': pos.lat, 'lon': pos.lon});

  /// Aplica configuração de fundeio (amarra, profundidade, raio manual...).
  Future<void> setConfig(AnchorConfig cfg) => _command('config', cfg.toJson());

  Future<void> _command(String cmd, [Map<String, dynamic>? args]) async {
    final payload = jsonEncode({'cmd': cmd, 'boat': boatId, if (args != null) 'args': args});
    // TODO(dev do MAIN): enviar pelo WS aberto, ou POST no relay:
    //   await http.post(Uri.parse('$relayBase/api/anchor/command'),
    //       headers: {'authorization': 'Bearer $relayToken', 'content-type': 'application/json'},
    //       body: payload);
    _log('comando (stub): $payload');
  }

  void dispose() => _snapshots.close();

  void _log(String m) {
    // ignore: avoid_print
    assert(() { print('[AnchorService] $m'); return true; }());
  }
}

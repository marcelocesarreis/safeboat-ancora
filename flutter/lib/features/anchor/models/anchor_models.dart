/// Modelos da Âncora Virtual do SAFEBOAT.
///
/// Espelham 1:1 a saída do núcleo `anchor-core.js` (a mesma lógica roda no
/// dispositivo a bordo e no protótipo web). O app pode:
///   a) receber os FIXES crus do SAFEBOAT e rodar o núcleo localmente (via FFI
///      do mesmo algoritmo ou reimplementado em Dart), para animação suave; ou
///   b) receber o SNAPSHOT já decidido a bordo — que é o modo recomendado,
///      porque o alarme continua valendo com o app fechado.
library;

/// Estado da vigília — igual ao enum STATE do núcleo.
enum AnchorState { idle, setting, armed, prealarm, alarm, nosignal }

AnchorState anchorStateFrom(String s) => AnchorState.values.firstWhere(
      (e) => e.name == s,
      orElse: () => AnchorState.idle,
    );

/// Coordenada simples.
class LatLng {
  final double lat;
  final double lon;
  const LatLng(this.lat, this.lon);
  factory LatLng.fromJson(Map j) => LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble());
  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};
}

/// Fix de posição — o contrato que todo dispositivo (simulado ou SAFEBOAT real)
/// entrega. Ver device-adapter.js.
class GpsFix {
  final int t; // epoch ms
  final double lat;
  final double lon;
  final double accuracy; // m
  final double? heading; // ° 0..360
  final double? cog;
  final double? sog; // m/s
  final double? depth; // m
  final bool novalid;

  const GpsFix({
    required this.t,
    required this.lat,
    required this.lon,
    required this.accuracy,
    this.heading,
    this.cog,
    this.sog,
    this.depth,
    this.novalid = false,
  });

  factory GpsFix.fromJson(Map j) => GpsFix(
        t: j['t'] as int,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        accuracy: (j['accuracy'] as num?)?.toDouble() ?? 8,
        heading: (j['heading'] as num?)?.toDouble(),
        cog: (j['cog'] as num?)?.toDouble(),
        sog: (j['sog'] as num?)?.toDouble(),
        depth: (j['depth'] as num?)?.toDouble(),
        novalid: j['novalid'] == true,
      );
}

/// Deriva do centro de giro — o diferencial do SAFEBOAT sobre alarmes só de raio.
class DriftInfo {
  final double rate; // m/min do centro de giro
  final double bearing; // ° da deriva
  final bool significant;
  final double accumulated; // m já migrados desde o início da deriva
  final double sinceMin;

  const DriftInfo({
    this.rate = 0,
    this.bearing = 0,
    this.significant = false,
    this.accumulated = 0,
    this.sinceMin = 0,
  });

  factory DriftInfo.fromJson(Map? j) => j == null
      ? const DriftInfo()
      : DriftInfo(
          rate: (j['rate'] as num?)?.toDouble() ?? 0,
          bearing: (j['brg'] as num?)?.toDouble() ?? 0,
          significant: j['significant'] == true,
          accumulated: (j['accumulated'] as num?)?.toDouble() ?? 0,
          sinceMin: (j['sinceMin'] as num?)?.toDouble() ?? 0,
        );
}

/// Snapshot completo da vigília — o que a UI desenha.
class AnchorSnapshot {
  final AnchorState state;
  final LatLng? anchor;
  final String? anchorSource; // marcado | ajuste-arco | manual | retroativo
  final double radius; // m
  final double scope; // relação de fundeio
  final LatLng? position; // posição atual (proa)
  final double distance; // m até a âncora
  final double bearing; // ° da âncora para o barco
  final double usage; // distance / radius (1.0 = no limite)
  final double maxRadiusSeen; // m — maior afastamento na noite
  final DriftInfo drift;
  final int outsideFor; // s fora do raio
  final double? accuracy; // m do GPS
  final double? heading; // ° proa
  final double? depth; // m

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
    this.depth,
  });

  factory AnchorSnapshot.fromJson(Map j) => AnchorSnapshot(
        state: anchorStateFrom(j['state'] as String? ?? 'idle'),
        anchor: j['anchor'] == null ? null : LatLng.fromJson(j['anchor'] as Map),
        anchorSource: j['anchorSource'] as String?,
        radius: (j['radius'] as num?)?.toDouble() ?? 0,
        scope: (j['scope'] as num?)?.toDouble() ?? 0,
        position: j['position'] == null ? null : LatLng.fromJson(j['position'] as Map),
        distance: (j['distance'] as num?)?.toDouble() ?? 0,
        bearing: (j['bearing'] as num?)?.toDouble() ?? 0,
        usage: (j['usage'] as num?)?.toDouble() ?? 0,
        maxRadiusSeen: (j['maxRadiusSeen'] as num?)?.toDouble() ?? 0,
        drift: DriftInfo.fromJson(j['drift'] as Map?),
        outsideFor: (j['outsideFor'] as num?)?.toInt() ?? 0,
        accuracy: (j['accuracy'] as num?)?.toDouble(),
        heading: (j['heading'] as num?)?.toDouble(),
        depth: (j['depth'] as num?)?.toDouble(),
      );

  bool get isActive => state != AnchorState.idle;
  bool get isAlarming => state == AnchorState.alarm;
}

/// Configuração do fundeio informada pelo usuário / calibração de instalação.
class AnchorConfig {
  double boatLength;
  double antennaToBow;
  double rodeLength;
  double depth;
  double bowRoller;
  double gpsMargin;
  double? alarmRadius; // null = calculado pelo scope

  AnchorConfig({
    this.boatLength = 8,
    this.antennaToBow = 4,
    this.rodeLength = 40,
    this.depth = 6,
    this.bowRoller = 1.2,
    this.gpsMargin = 5,
    this.alarmRadius,
  });

  Map<String, dynamic> toJson() => {
        'boatLength': boatLength,
        'antennaToBow': antennaToBow,
        'rodeLength': rodeLength,
        'depth': depth,
        'bowRoller': bowRoller,
        'gpsMargin': gpsMargin,
        if (alarmRadius != null) 'alarmRadius': alarmRadius,
      };

  /// Raio calculado (mesma fórmula do núcleo: alcance da amarra + barco + folga).
  double get computedRadius {
    final vertical = depth + bowRoller;
    final horizontal = rodeLength > vertical
        ? _sqrt(rodeLength * rodeLength - vertical * vertical)
        : 0.0;
    return horizontal + boatLength + gpsMargin;
  }

  double get scope {
    final vertical = depth + bowRoller;
    return vertical > 0 ? rodeLength / vertical : 0;
  }
}

double _sqrt(double v) => v <= 0 ? 0 : _newtonSqrt(v);
double _newtonSqrt(double v) {
  var x = v;
  for (var i = 0; i < 20; i++) {
    x = 0.5 * (x + v / x);
  }
  return x;
}

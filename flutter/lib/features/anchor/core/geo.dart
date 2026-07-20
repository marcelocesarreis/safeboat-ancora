/// SAFEBOAT — Geometria da Âncora Virtual (porta fiel de anchor-core.js).
///
/// Puro, sem dependência de Flutter. Trabalha num plano local ENU (x=leste,
/// y=norte, em metros) com origem numa coordenada de referência — o mesmo
/// truque do núcleo JS, que evita trigonometria esférica no laço quente.
library;

import 'dart:math' as math;

const double rEarth = 6371008.8;
const double d2r = math.pi / 180;
const double r2d = 180 / math.pi;

/// Ponto no plano local (metros).
class Vec {
  final double x;
  final double y;
  const Vec(this.x, this.y);
}

/// Coordenada geográfica.
class Geo {
  final double lat;
  final double lon;
  const Geo(this.lat, this.lon);
}

/// Metros por grau de latitude/longitude na latitude dada.
({double lat, double lon}) metersPerDegree(double lat) => (
      lat: 111132.92 - 559.82 * math.cos(2 * lat * d2r),
      lon: 111412.84 * math.cos(lat * d2r),
    );

/// lat/lon -> plano local ENU com origem em [ref].
Vec toLocal(Geo ref, Geo p) {
  final m = metersPerDegree(ref.lat);
  return Vec((p.lon - ref.lon) * m.lon, (p.lat - ref.lat) * m.lat);
}

/// plano local ENU -> lat/lon.
Geo fromLocal(Geo ref, Vec v) {
  final m = metersPerDegree(ref.lat);
  return Geo(ref.lat + v.y / m.lat, ref.lon + v.x / m.lon);
}

/// Distância em metros entre duas coordenadas (haversine).
double distance(Geo a, Geo b) {
  final dLat = (b.lat - a.lat) * d2r;
  final dLon = (b.lon - a.lon) * d2r;
  final la1 = a.lat * d2r, la2 = b.lat * d2r;
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(la1) * math.cos(la2) * math.pow(math.sin(dLon / 2), 2);
  return 2 * rEarth * math.asin(math.min(1, math.sqrt(h.toDouble())));
}

/// Rumo verdadeiro de a para b, em graus 0..360.
double bearing(Geo a, Geo b) {
  final dLon = (b.lon - a.lon) * d2r;
  final la1 = a.lat * d2r, la2 = b.lat * d2r;
  final y = math.sin(dLon) * math.cos(la2);
  final x = math.cos(la1) * math.sin(la2) -
      math.sin(la1) * math.cos(la2) * math.cos(dLon);
  return (math.atan2(y, x) * r2d + 360) % 360;
}

/// Desloca uma coordenada por distância (m) num rumo (graus).
Geo destination(Geo p, double dist, double brg) {
  final m = metersPerDegree(p.lat);
  final rad = brg * d2r;
  return Geo(
    p.lat + (dist * math.cos(rad)) / m.lat,
    p.lon + (dist * math.sin(rad)) / m.lon,
  );
}

/// Diferença angular assinada a-b em -180..180.
double angleDiff(double a, double b) => ((a - b + 540) % 360) - 180;

Vec centroid(List<Vec> pts) {
  double x = 0, y = 0;
  for (final p in pts) {
    x += p.x;
    y += p.y;
  }
  return Vec(x / pts.length, y / pts.length);
}

/// Resultado do ajuste de círculo.
class CircleFit {
  final double x;
  final double y;
  final double r;
  final double rms;
  final double span; // cobertura angular do arco (graus)
  const CircleFit(this.x, this.y, this.r, this.rms, this.span);
}

/// Resolve sistema linear 3x3 por eliminação de Gauss com pivotamento.
List<double>? _solve3(List<List<double>> a, List<double> b) {
  final m = [
    [a[0][0], a[0][1], a[0][2], b[0]],
    [a[1][0], a[1][1], a[1][2], b[1]],
    [a[2][0], a[2][1], a[2][2], b[2]],
  ];
  for (var i = 0; i < 3; i++) {
    var piv = i;
    for (var r = i + 1; r < 3; r++) {
      if (m[r][i].abs() > m[piv][i].abs()) piv = r;
    }
    if (m[piv][i].abs() < 1e-12) return null;
    final tmp = m[i];
    m[i] = m[piv];
    m[piv] = tmp;
    for (var r = 0; r < 3; r++) {
      if (r == i) continue;
      final f = m[r][i] / m[i][i];
      for (var c = i; c < 4; c++) {
        m[r][c] -= f * m[i][c];
      }
    }
  }
  return [m[0][3] / m[0][0], m[1][3] / m[1][1], m[2][3] / m[2][2]];
}

/// Maior cobertura angular contígua de uma lista de ângulos (graus).
double angularSpan(List<double> angs) {
  if (angs.length < 2) return 0;
  final s = angs.map((a) => (a + 360) % 360).toList()..sort();
  var maxGap = (s[0] + 360) - s[s.length - 1];
  for (var i = 1; i < s.length; i++) {
    maxGap = math.max(maxGap, s[i] - s[i - 1]);
  }
  return 360 - maxGap;
}

/// Ajuste algébrico de círculo (Kåsa) a pontos do plano local.
/// `span` abaixo de ~70° é mal-condicionado (arco curto cabe em infinitos
/// círculos) e não deve reposicionar a âncora.
CircleFit? fitCircle(List<Vec> pts) {
  final n = pts.length;
  if (n < 8) return null;
  double sx = 0, sy = 0;
  for (final p in pts) {
    sx += p.x;
    sy += p.y;
  }
  final cx0 = sx / n, cy0 = sy / n;
  double sxx = 0, sxy = 0, syy = 0, sxz = 0, syz = 0, sxs = 0, sys = 0, szs = 0;
  for (final p in pts) {
    final x = p.x - cx0, y = p.y - cy0, z = x * x + y * y;
    sxx += x * x;
    sxy += x * y;
    syy += y * y;
    sxz += x * z;
    syz += y * z;
    sxs += x;
    sys += y;
    szs += z;
  }
  final sol = _solve3(
    [
      [sxx, sxy, sxs],
      [sxy, syy, sys],
      [sxs, sys, n.toDouble()],
    ],
    [-sxz, -syz, -szs],
  );
  if (sol == null) return null;
  final d = sol[0], e = sol[1], f = sol[2];
  final cx = -d / 2, cy = -e / 2;
  final rr = cx * cx + cy * cy - f;
  if (!(rr > 0)) return null;
  final r = math.sqrt(rr);
  if (!r.isFinite || r > 500) return null;
  double sse = 0;
  final angs = <double>[];
  for (final p in pts) {
    final x = p.x - cx0 - cx, y = p.y - cy0 - cy;
    sse += math.pow(math.sqrt(x * x + y * y) - r, 2).toDouble();
    angs.add(math.atan2(y, x) * r2d);
  }
  return CircleFit(cx + cx0, cy + cy0, r, math.sqrt(sse / n), angularSpan(angs));
}

/// Raio de giro esperado (amarra retesada, pior caso):
///   horizontal = sqrt(amarra² − (prof + roleta)²) + comprimento + folga GPS.
double swingRadius({
  required double rodeLength,
  required double depth,
  double bowRoller = 1.2,
  double boatLength = 0,
  double gpsMargin = 5,
}) {
  final vertical = depth + bowRoller;
  final horizontal =
      rodeLength > vertical ? math.sqrt(rodeLength * rodeLength - vertical * vertical) : 0.0;
  return horizontal + boatLength + gpsMargin;
}

/// Relação de fundeio (scope) = amarra / (profundidade + roleta).
double scopeRatio({required double rodeLength, required double depth, double bowRoller = 1.2}) {
  final vertical = depth + bowRoller;
  return vertical > 0 ? rodeLength / vertical : 0.0;
}

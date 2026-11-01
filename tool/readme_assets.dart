// Generates the SVG sources for the README images.
//
//   dart run tool/readme_assets.dart <output-dir>
//
// tool/render_readme_assets.sh turns them into PNG / GIF files.

import 'dart:io';
import 'dart:math';

import 'package:tsp_route_finder/tsp_route_finder.dart';

const font =
    "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif";
const mono = "'SF Mono', Menlo, Consolas, monospace";
const ink = '#0f172a';
const muted = '#64748b';
const grid = '#e2e8f0';
const panelBg = '#f8fafc';
const red = '#e11d48';
const blue = '#2563eb';
const depotColor = '#f59e0b';
const vehicleColors = ['#2563eb', '#16a34a', '#db2777', '#ea580c', '#7c3aed'];

void main(List<String> args) {
  final out = Directory(args.isEmpty ? 'build/readme_assets' : args.first)
    ..createSync(recursive: true);
  final rnd = Random(2026);
  final stops = cityStops(rnd, 120);

  // 1. Before / after comparison.
  final all = [cairoDepot, ...stops];
  final nn = TspRouteFinder.solve(all, strategy: TspStrategy.nearestNeighbor);
  final opt = TspRouteFinder.solve(all, strategy: TspStrategy.optimized);
  File('${out.path}/before_after.svg')
      .writeAsStringSync(beforeAfter(all, nn, opt));

  // 2. Delivery plan with several vehicles.
  File('${out.path}/delivery.svg').writeAsStringSync(deliveryPlan(rnd));

  stdout.writeln('Wrote 2 images to ${out.path}');
}

const cairoDepot =
    TspLocation(latitude: 30.044, longitude: 31.236, name: 'Depot');

/// Clustered random points that look like neighborhoods of a city.
List<TspLocation> cityStops(Random rnd, int n) {
  final centers = [
    for (var i = 0; i < 7; i++)
      (29.93 + rnd.nextDouble() * 0.24, 31.12 + rnd.nextDouble() * 0.3),
  ];
  double gauss() {
    final u = 1 - rnd.nextDouble(), v = rnd.nextDouble();
    return sqrt(-2 * log(u)) * cos(2 * pi * v);
  }

  return [
    for (var i = 0; i < n; i++)
      () {
        if (rnd.nextDouble() < 0.25) {
          return TspLocation(
              latitude: 29.93 + rnd.nextDouble() * 0.24,
              longitude: 31.12 + rnd.nextDouble() * 0.3);
        }
        final c = centers[rnd.nextInt(centers.length)];
        return TspLocation(
            latitude: c.$1 + gauss() * 0.018,
            longitude: c.$2 + gauss() * 0.022);
      }(),
  ];
}

/// Maps lat/lng into a box, preserving the aspect ratio.
class Projection {
  Projection(List<TspLocation> pts, this.x0, this.y0, this.size) {
    final lats = pts.map((p) => p.latitude), lngs = pts.map((p) => p.longitude);
    minLat = lats.reduce(min);
    maxLat = lats.reduce(max);
    minLng = lngs.reduce(min);
    maxLng = lngs.reduce(max);
    k = cos((minLat + maxLat) / 2 * pi / 180);
    final w = (maxLng - minLng) * k, h = maxLat - minLat;
    scale = (size - 2 * pad) / max(w, h);
    offX = (size - w * scale) / 2;
    offY = (size - h * scale) / 2;
  }

  final double x0, y0, size;
  static const pad = 24.0;
  late double minLat, maxLat, minLng, maxLng, k, scale, offX, offY;

  String xy(TspLocation p) {
    final x = x0 + offX + (p.longitude - minLng) * k * scale;
    final y = y0 + offY + (maxLat - p.latitude) * scale;
    return '${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}';
  }
}

String svg(int w, int h, String body) =>
    '<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" '
    'viewBox="0 0 $w $h" font-family="$font">'
    '<rect width="$w" height="$h" fill="#ffffff"/>$body</svg>';

String text(num x, num y, String s,
        {int size = 16,
        String color = ink,
        String weight = '400',
        String anchor = 'start',
        String family = font}) =>
    '<text x="$x" y="$y" font-size="$size" fill="$color" font-family="$family" '
    'font-weight="$weight" text-anchor="$anchor">$s</text>';

String panel(num x, num y, num size) =>
    '<rect x="$x" y="$y" width="$size" height="$size" rx="14" '
    'fill="$panelBg" stroke="$grid"/>';

String polyline(
        Projection pr, List<TspLocation> pts, List<int> route, String color,
        {bool closed = true, double width = 2.2}) =>
    '<polyline fill="none" stroke="$color" stroke-width="$width" '
    'stroke-linejoin="round" stroke-linecap="round" points="'
    '${[
      ...route,
      if (closed) route.first
    ].map((i) => pr.xy(pts[i])).join(' ')}"/>';

String dots(Projection pr, List<TspLocation> pts, {int skip = 0}) {
  final b = StringBuffer();
  for (var i = skip; i < pts.length; i++) {
    final c = pr.xy(pts[i]).split(',');
    b.write('<circle cx="${c[0]}" cy="${c[1]}" r="3.4" fill="$ink"/>');
  }
  return b.toString();
}

String depot(Projection pr, TspLocation d) {
  final c = pr.xy(d).split(',').map(double.parse).toList();
  return '<rect x="${c[0] - 8}" y="${c[1] - 8}" width="16" height="16" '
      'rx="3" fill="$depotColor" stroke="#ffffff" stroke-width="2.5"/>';
}

String km(double v) => '${v.toStringAsFixed(1)} km';

String beforeAfter(List<TspLocation> pts, TspResult nn, TspResult opt) {
  const w = 1200, h = 770, size = 560.0, top = 186.0;
  final left = Projection(pts, 24, top, size);
  final right = Projection(pts, 616, top, size);
  final saved = (1 - opt.totalDistance / nn.totalDistance) * 100;
  return svg(
      w,
      h,
      [
        text(24, 46, 'tsp_route_finder: ${pts.length - 1} stops around Cairo',
            size: 26, weight: '700'),
        text(24, 78,
            'Same stops, same start. The optimized route is ${saved.toStringAsFixed(0)}% shorter.',
            size: 17, color: muted),
        panel(24, top, size),
        panel(616, top, size),
        polyline(left, pts, nn.route, red),
        polyline(right, pts, opt.route, blue),
        dots(left, pts, skip: 1),
        dots(right, pts, skip: 1),
        depot(left, pts[0]),
        depot(right, pts[0]),
        text(24, top - 44, 'Nearest neighbor (v0.0.x)',
            size: 18, weight: '600'),
        text(24, top - 16, km(nn.totalDistance),
            size: 17, color: red, weight: '600'),
        text(616, top - 44, 'Optimized: 2-opt + Or-opt (v0.1+)',
            size: 18, weight: '600'),
        text(616, top - 16,
            '${km(opt.totalDistance)}  (−${saved.toStringAsFixed(0)}%)',
            size: 17, color: blue, weight: '600'),
      ].join());
}

String deliveryPlan(Random rnd) {
  final stopsLoc = cityStops(rnd, 70);
  final stops = [
    for (final l in stopsLoc)
      DeliveryStop(
        location: l,
        demand: 1 + rnd.nextInt(4).toDouble(),
        serviceTime: 5,
      ),
  ];
  const vehicles = [
    Vehicle(name: 'Ahmed', capacity: 45, shift: TimeWindow(0, 480)),
    Vehicle(name: 'Sara', capacity: 45, shift: TimeWindow(0, 480)),
    Vehicle(name: 'Omar', capacity: 45, shift: TimeWindow(0, 480)),
    Vehicle(name: 'Mona', capacity: 45, shift: TimeWindow(0, 480)),
  ];
  final plan =
      RoutePlanner.plan(depot: cairoDepot, stops: stops, vehicles: vehicles);

  const w = 1200, h = 700, size = 560.0, top = 110.0;
  final pts = [cairoDepot, ...stopsLoc];
  final pr = Projection(pts, 24, top, size);
  final body = StringBuffer()
    ..write(text(
        24,
        46,
        'RoutePlanner: ${stops.length} deliveries, '
        '${vehicles.length} drivers',
        size: 26,
        weight: '700'))
    ..write(text(24, 78,
        'Capacity, service times and shifts respected. Total ${km(plan.totalDistance)}.',
        size: 17, color: muted))
    ..write(panel(24, top, size));
  for (final r in plan.routes) {
    if (r.isEmpty) continue;
    final route = [0, for (final s in r.stops) s + 1];
    body.write(
        polyline(pr, pts, route, vehicleColors[r.vehicleIndex], width: 2.6));
  }
  for (final r in plan.routes) {
    for (final s in r.stops) {
      final c = pr.xy(pts[s + 1]).split(',');
      body.write('<circle cx="${c[0]}" cy="${c[1]}" r="4.2" '
          'fill="${vehicleColors[r.vehicleIndex]}" stroke="#ffffff" '
          'stroke-width="1.5"/>');
    }
  }
  body.write(depot(pr, cairoDepot));

  var y = top + 40;
  body.write(text(632, y, 'Driver', size: 15, color: muted, weight: '600'));
  body.write(text(800, y, 'Stops', size: 15, color: muted, weight: '600'));
  body.write(text(890, y, 'Load', size: 15, color: muted, weight: '600'));
  body.write(text(990, y, 'Distance', size: 15, color: muted, weight: '600'));
  body.write(text(1100, y, 'Back at', size: 15, color: muted, weight: '600'));
  y += 16;
  for (final r in plan.routes) {
    y += 46;
    final v = vehicles[r.vehicleIndex];
    final end = 8 * 60 + r.endTime; // Shift starts at 08:00.
    final hhmm = '${(end ~/ 60).toString().padLeft(2, '0')}:'
        '${(end % 60).floor().toString().padLeft(2, '0')}';
    body
      ..write('<rect x="632" y="${y - 15}" width="18" height="18" rx="4" '
          'fill="${vehicleColors[r.vehicleIndex]}"/>')
      ..write(text(660, y, v.name!, size: 18, weight: '600'))
      ..write(text(800, y, '${r.stops.length}', size: 18))
      ..write(
          text(890, y, '${r.load.toInt()} / ${v.capacity.toInt()}', size: 18))
      ..write(text(990, y, km(r.distance), size: 18))
      ..write(text(1100, y, hhmm, size: 18));
  }
  y += 60;
  body
    ..write('<line x1="632" y1="$y" x2="1176" y2="$y" stroke="$grid"/>')
    ..write(text(632, y + 40, 'RoutePlanner.plan(',
        size: 16, color: ink, weight: '600', family: mono))
    ..write(text(652, y + 66, 'depot: warehouse,',
        size: 16, color: muted, family: mono))
    ..write(text(652, y + 92, 'stops: deliveries,',
        size: 16, color: muted, family: mono))
    ..write(text(652, y + 118, 'vehicles: drivers,',
        size: 16, color: muted, family: mono))
    ..write(text(632, y + 144, ')', size: 16, weight: '600', family: mono));
  return svg(w, h, body.toString());
}

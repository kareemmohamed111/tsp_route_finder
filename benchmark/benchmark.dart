// Compares the strategies on random stops around Cairo.
// Run with: dart run benchmark/benchmark.dart
import 'dart:math';

import 'package:tsp_route_finder/tsp_route_finder.dart';

void main() {
  final rnd = Random(1);
  print(
      '| Stops | Nearest neighbor (0.0.x) | Optimized | Exact | Time (optimized) |');
  print('|---:|---:|---:|---:|---:|');
  for (final n in [10, 12, 50, 100, 250, 500, 1000]) {
    const trials = 5;
    var nnSum = 0.0, optSum = 0.0, exactSum = 0.0;
    var ms = 0;
    for (var t = 0; t < trials; t++) {
      final stops = [
        for (var i = 0; i < n; i++)
          TspLocation(
            latitude: 29.8 + rnd.nextDouble() * 0.5,
            longitude: 31.0 + rnd.nextDouble() * 0.6,
          ),
      ];
      nnSum +=
          TspRouteFinder.solve(stops, strategy: TspStrategy.nearestNeighbor)
              .totalDistance;
      final sw = Stopwatch()..start();
      optSum += TspRouteFinder.solve(stops, strategy: TspStrategy.optimized)
          .totalDistance;
      ms += sw.elapsedMilliseconds;
      if (n <= TspRouteFinder.maxExactSize) {
        exactSum += TspRouteFinder.solve(stops, strategy: TspStrategy.exact)
            .totalDistance;
      }
    }
    String pct(double v, double base) =>
        '${((v / base - 1) * 100).toStringAsFixed(1)}%';
    final base = exactSum > 0 ? exactSum : optSum;
    print('| $n | ${(nnSum / trials).toStringAsFixed(1)} km '
        '(+${pct(nnSum, base)}) '
        '| ${(optSum / trials).toStringAsFixed(1)} km'
        '${exactSum > 0 ? ' (+${pct(optSum, base)})' : ''} '
        '| ${exactSum > 0 ? '${(exactSum / trials).toStringAsFixed(1)} km' : 'n/a'} '
        '| ${(ms / trials).toStringAsFixed(0)} ms |');
  }
}

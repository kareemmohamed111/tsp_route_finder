import 'dart:math';

import 'package:test/test.dart';
import 'package:tsp_route_finder/tsp_route_finder.dart';

const egypt = [
  TspLocation(latitude: 30.0454, longitude: 31.2332, name: 'Cairo'),
  TspLocation(latitude: 30.7865, longitude: 31.0012, name: 'Tanta'),
  TspLocation(latitude: 31.0407, longitude: 31.3804, name: 'Mansoura'),
  TspLocation(latitude: 24.0895, longitude: 32.8993, name: 'Aswan'),
  TspLocation(latitude: 31.2009, longitude: 29.9278, name: 'Alexandria'),
];

List<TspLocation> randomLocations(Random rnd, int n) => [
      for (var i = 0; i < n; i++)
        TspLocation(
          latitude: 29 + rnd.nextDouble() * 3,
          longitude: 29 + rnd.nextDouble() * 4,
        ),
    ];

List<List<double>> randomMatrix(Random rnd, int n, {bool symmetric = true}) {
  final m = List.generate(n, (_) => List<double>.filled(n, 0));
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      if (i == j) continue;
      if (symmetric && j < i) {
        m[i][j] = m[j][i];
      } else {
        m[i][j] = 1 + rnd.nextInt(100).toDouble();
      }
    }
  }
  return m;
}

double matrixCost(List<List<double>> m, List<int> r, bool closed) {
  var c = 0.0;
  for (var k = 0; k + 1 < r.length; k++) {
    c += m[r[k]][r[k + 1]];
  }
  if (closed && r.length > 1) c += m[r.last][r.first];
  return c;
}

/// Brute-force optimum by trying every permutation.
double bruteForce(List<List<double>> m, int start, int? end, bool closed) {
  final n = m.length;
  final inner = [
    for (var i = 0; i < n; i++)
      if (i != start && i != end) i
  ];
  var best = double.infinity;
  void permute(int k) {
    if (k == inner.length) {
      final r = [start, ...inner, if (end != null) end];
      best = min(best, matrixCost(m, r, closed));
      return;
    }
    for (var i = k; i < inner.length; i++) {
      final t = inner[k];
      inner[k] = inner[i];
      inner[i] = t;
      permute(k + 1);
      inner[i] = inner[k];
      inner[k] = t;
    }
  }

  permute(0);
  return best;
}

void expectValidRoute(TspResult r, int n, int start, [int? end]) {
  expect(r.route.length, n);
  expect(r.route.toSet().length, n, reason: 'every stop exactly once');
  expect(r.route.first, start);
  if (end != null) expect(r.route.last, end);
}

void main() {
  group('haversineDistance', () {
    test('Cairo to Alexandria is about 180 km', () {
      expect(egypt[0].distanceTo(egypt[4]), closeTo(180, 3));
    });

    test('is zero for the same point and symmetric', () {
      expect(haversineDistance(egypt[0], egypt[0]), 0);
      expect(haversineDistance(egypt[1], egypt[3]),
          closeTo(haversineDistance(egypt[3], egypt[1]), 1e-9));
    });

    test('handles antipodal points', () {
      const a = TspLocation(latitude: 0, longitude: 0);
      const b = TspLocation(latitude: 0, longitude: 180);
      expect(a.distanceTo(b), closeTo(pi * earthRadiusKm, 1e-6));
    });
  });

  group('edge cases', () {
    test('empty input', () {
      final r = TspRouteFinder.solve(const []);
      expect(r.route, isEmpty);
      expect(r.totalDistance, 0);
    });

    test('single stop', () {
      final r = TspRouteFinder.solve([egypt[0]]);
      expect(r.route, [0]);
      expect(r.totalDistance, 0);
      expect(r.closedRoute, [0]);
    });

    test('two stops round trip', () {
      final r = TspRouteFinder.solve(egypt.sublist(0, 2), startIndex: 1);
      expect(r.route, [1, 0]);
      expect(r.closedRoute, [1, 0, 1]);
      expect(r.totalDistance, closeTo(2 * egypt[0].distanceTo(egypt[1]), 1e-9));
    });

    test('duplicate locations', () {
      final r = TspRouteFinder.solve([egypt[0], egypt[0], egypt[1], egypt[1]],
          strategy: TspStrategy.optimized);
      expectValidRoute(r, 4, 0);
    });

    test('invalid arguments throw', () {
      expect(() => TspRouteFinder.solve(egypt, startIndex: 5),
          throwsA(isA<RangeError>()));
      expect(() => TspRouteFinder.solve(egypt, startIndex: -1),
          throwsA(isA<RangeError>()));
      expect(
          () => TspRouteFinder.solve(egypt, endIndex: 2), throwsArgumentError,
          reason: 'endIndex needs returnToStart: false');
      expect(
          () => TspRouteFinder.solve(egypt, endIndex: 0, returnToStart: false),
          throwsArgumentError);
      expect(
          () => TspRouteFinder.solve(randomLocations(Random(1), 17),
              strategy: TspStrategy.exact),
          throwsArgumentError);
      expect(
          () => TspRouteFinder.solveMatrix([
                [0, 1],
                [1]
              ]),
          throwsArgumentError);
      expect(
          () => TspRouteFinder.solveMatrix([
                [0, -1],
                [1, 0]
              ]),
          throwsArgumentError);
      expect(() => TspRouteFinder.solve(egypt, distance: (a, b) => double.nan),
          throwsArgumentError);
    });
  });

  group('exact solver matches brute force', () {
    final rnd = Random(42);
    for (final symmetric in [true, false]) {
      for (final mode in ['closed', 'open', 'fixedEnd']) {
        test('${symmetric ? 'symmetric' : 'asymmetric'} $mode', () {
          for (var trial = 0; trial < 15; trial++) {
            final n = 2 + rnd.nextInt(7);
            final m = randomMatrix(rnd, n, symmetric: symmetric);
            final start = rnd.nextInt(n);
            final end = mode == 'fixedEnd' ? (start + 1) % n : null;
            final closed = mode == 'closed';
            final r = TspRouteFinder.solveMatrix(m,
                startIndex: start,
                endIndex: end,
                returnToStart: closed,
                strategy: TspStrategy.exact);
            expectValidRoute(r, n, start, end);
            expect(r.isOptimal, isTrue);
            expect(
                r.totalDistance, closeTo(matrixCost(m, r.route, closed), 1e-9));
            expect(r.totalDistance,
                closeTo(bruteForce(m, start, end, closed), 1e-9));
          }
        });
      }
    }
  });

  group('optimized solver', () {
    test('produces valid routes in every mode, symmetric and asymmetric', () {
      final rnd = Random(7);
      for (var trial = 0; trial < 60; trial++) {
        final n = 2 + rnd.nextInt(60);
        final symmetric = trial.isEven;
        final m = randomMatrix(rnd, n, symmetric: symmetric);
        final start = rnd.nextInt(n);
        final mode = trial % 3;
        final closed = mode == 0;
        final end =
            mode == 2 && n > 1 ? (start + 1 + rnd.nextInt(n - 1)) % n : null;
        final r = TspRouteFinder.solveMatrix(m,
            startIndex: start,
            endIndex: end,
            returnToStart: closed,
            strategy: TspStrategy.optimized);
        expectValidRoute(r, n, start, end);
        expect(r.totalDistance, closeTo(matrixCost(m, r.route, closed), 1e-6));
      }
    });

    test('is never worse than nearest neighbor and close to optimal', () {
      final rnd = Random(2024);
      var gapSum = 0.0;
      const trials = 40;
      for (var trial = 0; trial < trials; trial++) {
        final locations = randomLocations(rnd, 11);
        final nn = TspRouteFinder.solve(locations,
            strategy: TspStrategy.nearestNeighbor);
        final opt =
            TspRouteFinder.solve(locations, strategy: TspStrategy.optimized);
        final exact =
            TspRouteFinder.solve(locations, strategy: TspStrategy.exact);
        expect(opt.totalDistance, lessThanOrEqualTo(nn.totalDistance + 1e-9));
        expect(
            exact.totalDistance, lessThanOrEqualTo(opt.totalDistance + 1e-9));
        gapSum += opt.totalDistance / exact.totalDistance - 1;
      }
      expect(gapSum / trials, lessThan(0.03),
          reason: 'average gap to optimal should be under 3%');
    });

    test('solves 1000 stops quickly', () {
      final locations = randomLocations(Random(3), 1000);
      final sw = Stopwatch()..start();
      final r = TspRouteFinder.solve(locations);
      expectValidRoute(r, 1000, 0);
      expect(r.strategy, TspStrategy.optimized);
      expect(sw.elapsed, lessThan(const Duration(seconds: 20)));
    });

    test('respects timeLimit and still returns a valid route', () {
      final locations = randomLocations(Random(4), 1500);
      final r = TspRouteFinder.solve(locations,
          strategy: TspStrategy.optimized,
          timeLimit: const Duration(milliseconds: 50));
      expectValidRoute(r, 1500, 0);
    });
  });

  group('API', () {
    test('auto picks exact for small and optimized for large inputs', () {
      expect(TspRouteFinder.solve(egypt).strategy, TspStrategy.exact);
      expect(TspRouteFinder.solve(egypt).isOptimal, isTrue);
      expect(TspRouteFinder.solve(randomLocations(Random(5), 40)).strategy,
          TspStrategy.optimized);
    });

    test('one-way route with fixed end', () {
      final r = TspRouteFinder.solve(egypt,
          startIndex: 0, endIndex: 3, returnToStart: false);
      expectValidRoute(r, 5, 0, 3);
      expect(r.returnsToStart, isFalse);
      expect(r.closedRoute, r.route);
    });

    test('one-way route is never longer than the round trip', () {
      final open = TspRouteFinder.solve(egypt, returnToStart: false);
      final closed = TspRouteFinder.solve(egypt);
      expect(open.totalDistance, lessThanOrEqualTo(closed.totalDistance));
    });

    test('reorder and routeDistance', () {
      final r = TspRouteFinder.solve(egypt);
      final names = r.reorder(egypt).map((l) => l.name).toList();
      expect(names.first, 'Cairo');
      expect(names.toSet().length, 5);
      expect(TspRouteFinder.routeDistance(egypt, r.route),
          closeTo(r.totalDistance, 1e-9));
    });

    test('custom distance function', () {
      double manhattan(TspLocation a, TspLocation b) =>
          (a.latitude - b.latitude).abs() + (a.longitude - b.longitude).abs();
      final r = TspRouteFinder.solve(egypt, distance: manhattan);
      expectValidRoute(r, 5, 0);
      expect(TspRouteFinder.routeDistance(egypt, r.route, distance: manhattan),
          closeTo(r.totalDistance, 1e-9));
    });

    test('route is unmodifiable', () {
      final r = TspRouteFinder.solve(egypt);
      expect(() => r.route.add(1), throwsUnsupportedError);
    });
  });

  group('legacy 0.0.3 API', () {
    // ignore_for_file: deprecated_member_use_from_same_package
    final cities = [
      for (final l in egypt)
        CitiesLocations(
            cityName: l.name!, latitude: l.latitude, longitude: l.longitude),
    ];

    test('TspPackage.calculateTspRoute still works', () async {
      final route = await TspPackage.calculateTspRoute(
          locations: cities, startingLocationIndex: 0);
      expect(route.first, 0);
      expect(route.toSet().length, 5);
      expect(cities.first.cityName, 'Cairo');
    });

    test('calculateTspRoute validates the start index', () {
      expect(
          () => TspPackage.calculateTspRoute(
              locations: cities, startingLocationIndex: 9),
          throwsArgumentError);
    });

    test('tspNearestNeighbor returns independent lists', () {
      final a = tspNearestNeighbor(cities, 0);
      final b = tspNearestNeighbor(cities, 1);
      expect(a.first, 0);
      expect(b.first, 1);
    });

    test('calculateDistance and radians', () {
      expect(calculateDistance(cities[0], cities[4]),
          closeTo(cities[0].distanceTo(cities[4]), 1e-9));
      expect(radians(180), closeTo(pi, 1e-12));
    });
  });
}

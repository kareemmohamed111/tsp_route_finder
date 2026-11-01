import 'dart:math';

import 'package:test/test.dart';
import 'package:tsp_route_finder/tsp_route_finder.dart';

const depot = TspLocation(latitude: 30.05, longitude: 31.24, name: 'Depot');
const speed = 40.0;

double travelMinutes(TspLocation a, TspLocation b) =>
    a.distanceTo(b) / speed * 60;

List<DeliveryStop> randomStops(
  Random rnd,
  int n, {
  bool demands = false,
  bool windows = false,
  bool service = false,
}) =>
    [
      for (var i = 0; i < n; i++)
        DeliveryStop(
          location: TspLocation(
            latitude: 29.9 + rnd.nextDouble() * 0.3,
            longitude: 31.1 + rnd.nextDouble() * 0.3,
          ),
          demand: demands ? 1 + rnd.nextInt(5).toDouble() : 0,
          serviceTime: service ? 5 : 0,
          timeWindow: windows
              ? (() {
                  final open = rnd.nextInt(180).toDouble();
                  return TimeWindow(open, open + 60 + rnd.nextInt(120));
                })()
              : null,
        ),
    ];

/// Independently re-simulates a route. Returns its distance, or null if it
/// breaks a constraint.
double? simulate(List<DeliveryStop> stops, Vehicle v, List<int> route) {
  if (route.isEmpty) return 0;
  if (v.maxStops != null && route.length > v.maxStops!) return null;
  final load = route.fold(0.0, (s, i) => s + stops[i].demand);
  if (load > v.capacity + 1e-9) return null;
  final start = v.start ?? depot;
  final end = v.end ?? (v.returnToStart ? start : null);
  final shift = v.shift ?? TimeWindow.unlimited;
  var t = shift.earliest;
  var dist = 0.0;
  var prev = start;
  for (final i in route) {
    final s = stops[i];
    dist += prev.distanceTo(s.location);
    t += travelMinutes(prev, s.location);
    final w = s.timeWindow ?? TimeWindow.unlimited;
    t = max(t, w.earliest);
    if (t > w.latest + 1e-6) return null;
    t += s.serviceTime;
    prev = s.location;
  }
  if (end != null) {
    dist += prev.distanceTo(end);
    t += travelMinutes(prev, end);
  }
  if (t > shift.latest + 1e-6) return null;
  return dist;
}

void expectValidPlan(
    RoutePlan plan, List<DeliveryStop> stops, List<Vehicle> vehicles) {
  expect(plan.routes.length, vehicles.length);
  final seen = <int>[
    for (final r in plan.routes) ...r.stops,
    ...plan.unassigned,
  ];
  expect(seen.length, stops.length, reason: 'every stop exactly once');
  expect(seen.toSet().length, stops.length, reason: 'no duplicates');
  for (final r in plan.routes) {
    final d = simulate(stops, vehicles[r.vehicleIndex], r.stops);
    expect(d, isNotNull, reason: 'route ${r.vehicleIndex} is feasible');
    expect(r.distance, closeTo(d!, 1e-6));
    expect(r.arrivalTimes.length, r.stops.length);
    for (var k = 0; k < r.stops.length; k++) {
      final w = stops[r.stops[k]].timeWindow ?? TimeWindow.unlimited;
      expect(r.serviceStartTimes[k], greaterThanOrEqualTo(r.arrivalTimes[k]));
      expect(
          w.contains(r.serviceStartTimes[k]) ||
              (r.serviceStartTimes[k] - w.latest).abs() < 1e-6,
          isTrue);
    }
  }
}

/// Best possible total distance by trying every assignment and order.
double bruteForce(List<DeliveryStop> stops, List<Vehicle> vehicles) {
  final n = stops.length, k = vehicles.length;
  var best = double.infinity;
  final assignment = List.filled(n, 0);

  double bestOrder(int v, List<int> items) {
    var b = double.infinity;
    void permute(int i) {
      if (i == items.length) {
        final d = simulate(stops, vehicles[v], items);
        if (d != null && d < b) b = d;
        return;
      }
      for (var j = i; j < items.length; j++) {
        final t = items[i];
        items[i] = items[j];
        items[j] = t;
        permute(i + 1);
        items[j] = items[i];
        items[i] = t;
      }
    }

    permute(0);
    return b;
  }

  void assign(int i) {
    if (i == n) {
      var total = 0.0;
      for (var v = 0; v < k; v++) {
        total += bestOrder(v, [
          for (var s = 0; s < n; s++)
            if (assignment[s] == v) s
        ]);
        if (total >= best) return;
      }
      best = total;
      return;
    }
    for (var v = 0; v < k; v++) {
      assignment[i] = v;
      assign(i + 1);
    }
  }

  assign(0);
  return best;
}

RoutePlan planFor(List<DeliveryStop> stops, List<Vehicle> vehicles,
        {bool balance = false}) =>
    RoutePlanner.plan(
      depot: depot,
      stops: stops,
      vehicles: vehicles,
      averageSpeedKmh: speed,
      balance: balance,
    );

void main() {
  group('RoutePlanner basics', () {
    test('no stops', () {
      final plan = planFor(const [], const [Vehicle(), Vehicle()]);
      expect(plan.routes.every((r) => r.isEmpty), isTrue);
      expect(plan.totalDistance, 0);
      expect(plan.isComplete, isTrue);
      expect(plan.usedVehicleCount, 0);
    });

    test('one vehicle without constraints matches the TSP solver', () {
      final rnd = Random(11);
      for (var trial = 0; trial < 10; trial++) {
        final stops = randomStops(rnd, 10);
        final plan = planFor(stops, const [Vehicle()]);
        final tsp = TspRouteFinder.solve(
            [depot, for (final s in stops) s.location],
            strategy: TspStrategy.exact);
        expectValidPlan(plan, stops, const [Vehicle()]);
        expect(plan.totalDistance,
            lessThanOrEqualTo(tsp.totalDistance * 1.03 + 1e-9));
      }
    });

    test('invalid arguments throw', () {
      final stops = randomStops(Random(1), 3);
      expect(() => planFor(stops, const []), throwsArgumentError);
      expect(() => RoutePlanner.plan(stops: stops, vehicles: const [Vehicle()]),
          throwsArgumentError,
          reason: 'no depot and no vehicle start');
      expect(
          () => RoutePlanner.plan(
              depot: depot,
              stops: stops,
              vehicles: const [Vehicle()],
              averageSpeedKmh: 0),
          throwsArgumentError);
      expect(
          () => planFor([
                DeliveryStop(location: depot, demand: -1),
              ], const [
                Vehicle()
              ]),
          throwsArgumentError);
    });
  });

  group('constraints', () {
    test('capacity splits stops between vehicles', () {
      final stops = randomStops(Random(2), 20, demands: true);
      final total = stops.fold(0.0, (s, x) => s + x.demand);
      final vehicles = [
        for (var i = 0; i < 4; i++)
          Vehicle(capacity: (total / 3).ceilToDouble())
      ];
      final plan = planFor(stops, vehicles);
      expectValidPlan(plan, stops, vehicles);
      expect(plan.isComplete, isTrue);
      expect(plan.usedVehicleCount, greaterThanOrEqualTo(3));
    });

    test('time windows, service times and shifts are respected', () {
      final rnd = Random(3);
      for (var trial = 0; trial < 10; trial++) {
        final stops =
            randomStops(rnd, 25, demands: true, windows: true, service: true);
        final vehicles = [
          const Vehicle(capacity: 30, shift: TimeWindow(0, 360)),
          const Vehicle(capacity: 30, shift: TimeWindow(0, 360)),
          const Vehicle(capacity: 20, shift: TimeWindow(60, 300)),
        ];
        final plan = planFor(stops, vehicles);
        expectValidPlan(plan, stops, vehicles);
      }
    });

    test('impossible stops are reported as unassigned', () {
      final stops = [
        const DeliveryStop(
            location: TspLocation(latitude: 30.1, longitude: 31.3), demand: 2),
        const DeliveryStop(
            location: TspLocation(latitude: 30.0, longitude: 31.2), demand: 99),
        const DeliveryStop(
            location: TspLocation(latitude: 31.2, longitude: 29.9),
            timeWindow: TimeWindow(0, 10)), // Alexandria in 10 minutes.
      ];
      const vehicles = [Vehicle(capacity: 10)];
      final plan = planFor(stops, vehicles);
      expectValidPlan(plan, stops, vehicles);
      expect(plan.unassigned, [1, 2]);
      expect(plan.isComplete, isFalse);
      expect(plan.routes.single.stops, [0]);
    });

    test('maxStops and balance', () {
      final stops = randomStops(Random(4), 10);
      final vehicles = const [Vehicle(), Vehicle(), Vehicle()];
      final unbalanced = planFor(stops, vehicles);
      expectValidPlan(unbalanced, stops, vehicles);
      final balanced = planFor(stops, vehicles, balance: true);
      expectValidPlan(balanced, stops, vehicles);
      for (final r in balanced.routes) {
        expect(r.stops.length, lessThanOrEqualTo(4));
      }
      expect(balanced.usedVehicleCount, 3);

      const limited = [Vehicle(maxStops: 2), Vehicle(maxStops: 3)];
      final plan = planFor(stops, limited);
      expectValidPlan(plan, stops, limited);
      expect(plan.unassigned.length, 5);
    });

    test('own start/end locations and one-way routes', () {
      final stops = randomStops(Random(5), 12);
      const home = TspLocation(latitude: 30.2, longitude: 31.4, name: 'Home');
      const vehicles = [
        Vehicle(end: home),
        Vehicle(start: home, returnToStart: false),
      ];
      final plan = planFor(stops, vehicles);
      expectValidPlan(plan, stops, vehicles);
      expect(plan.isComplete, isTrue);
    });
  });

  group('quality', () {
    test('close to the brute-force optimum on small instances', () {
      final rnd = Random(6);
      var gapSum = 0.0;
      const trials = 12;
      for (var trial = 0; trial < trials; trial++) {
        final stops = randomStops(rnd, 6,
            demands: true, windows: trial.isOdd, service: true);
        final vehicles = [
          const Vehicle(capacity: 12, shift: TimeWindow(0, 400)),
          const Vehicle(capacity: 9, shift: TimeWindow(0, 400)),
        ];
        final optimum = bruteForce(stops, vehicles);
        final plan = planFor(stops, vehicles);
        expectValidPlan(plan, stops, vehicles);
        if (optimum.isInfinite) continue;
        if (plan.isComplete) {
          gapSum += plan.totalDistance / optimum - 1;
        } else {
          gapSum += 1; // Count a missed feasible stop as a 100% gap.
        }
      }
      expect(gapSum / trials, lessThan(0.05));
    });

    test('200 stops and 5 vehicles stay fast', () {
      final stops = randomStops(Random(8), 200,
          demands: true, windows: true, service: true);
      final vehicles = [
        for (var i = 0; i < 5; i++)
          const Vehicle(capacity: 150, shift: TimeWindow(0, 600)),
      ];
      final sw = Stopwatch()..start();
      final plan = planFor(stops, vehicles);
      expectValidPlan(plan, stops, vehicles);
      expect(sw.elapsed, lessThan(const Duration(seconds: 20)));
    });
  });
}

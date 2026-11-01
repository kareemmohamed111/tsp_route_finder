import 'dart:math';

import 'package:test/test.dart';
import 'package:tsp_route_finder/tsp_route_finder.dart';

double manhattan(TspLocation a, TspLocation b) =>
    (a.latitude - b.latitude).abs() + (a.longitude - b.longitude).abs();

void main() {
  final rnd = Random(12);
  final locations = [
    for (var i = 0; i < 300; i++)
      TspLocation(
          latitude: 30 + rnd.nextDouble(), longitude: 31 + rnd.nextDouble()),
  ];

  test('solveAsync matches solve', () async {
    final sync = TspRouteFinder.solve(locations, startIndex: 4);
    final async = await TspRouteFinder.solveAsync(locations, startIndex: 4);
    expect(async.route, sync.route);
    expect(async.totalDistance, sync.totalDistance);
  });

  test('solveAsync accepts a top-level distance function', () async {
    final sync = TspRouteFinder.solve(locations, distance: manhattan);
    final async =
        await TspRouteFinder.solveAsync(locations, distance: manhattan);
    expect(async.route, sync.route);
  });

  test('solveMatrixAsync matches solveMatrix', () async {
    final matrix = [
      for (final a in locations.take(40))
        [for (final b in locations.take(40)) a.distanceTo(b)],
    ];
    final sync = TspRouteFinder.solveMatrix(matrix, returnToStart: false);
    final async =
        await TspRouteFinder.solveMatrixAsync(matrix, returnToStart: false);
    expect(async.route, sync.route);
  });

  test('errors are delivered through the future', () {
    expect(TspRouteFinder.solveAsync(locations, startIndex: 999),
        throwsA(isA<RangeError>()));
  });

  test('planAsync matches plan', () async {
    final stops = [
      for (final l in locations.take(60)) DeliveryStop(location: l, demand: 1),
    ];
    final vehicles = const [
      Vehicle(capacity: 25),
      Vehicle(capacity: 25),
      Vehicle(capacity: 25)
    ];
    final depot = locations.last;
    final sync =
        RoutePlanner.plan(depot: depot, stops: stops, vehicles: vehicles);
    final async = await RoutePlanner.planAsync(
        depot: depot, stops: stops, vehicles: vehicles);
    expect([for (final r in async.routes) r.stops],
        [for (final r in sync.routes) r.stops]);
    expect(async.totalDistance, closeTo(sync.totalDistance, 1e-9));
  });
}

// Run with: dart run example/main.dart
//
// In a Flutter app the same calls work unchanged, for example inside a
// button's onPressed callback. Use the result to reorder markers or draw a
// polyline on google_maps_flutter, flutter_map, etc.

import 'package:tsp_route_finder/tsp_route_finder.dart';

Future<void> main() async {
  const stops = [
    TspLocation(latitude: 30.0454, longitude: 31.2332, name: 'Cairo'),
    TspLocation(latitude: 30.7865, longitude: 31.0012, name: 'Tanta'),
    TspLocation(latitude: 31.0407, longitude: 31.3804, name: 'Mansoura'),
    TspLocation(latitude: 24.0895, longitude: 32.8993, name: 'Aswan'),
    TspLocation(latitude: 31.2009, longitude: 29.9278, name: 'Alexandria'),
    TspLocation(latitude: 25.6872, longitude: 32.6396, name: 'Luxor'),
    TspLocation(latitude: 31.2653, longitude: 32.3019, name: 'Port Said'),
  ];

  // 1. Round trip starting and ending in Cairo (index 0).
  final roundTrip = TspRouteFinder.solve(stops, startIndex: 0);
  print('Round trip: ${_names(roundTrip.reorder(stops))} -> Cairo');
  print('  ${roundTrip.totalDistance.toStringAsFixed(1)} km, '
      'optimal: ${roundTrip.isOptimal}\n');

  // 2. One-way trip from Cairo that must finish in Aswan (index 3).
  final oneWay = TspRouteFinder.solve(
    stops,
    startIndex: 0,
    endIndex: 3,
    returnToStart: false,
  );
  print('One way:    ${_names(oneWay.reorder(stops))}');
  print('  ${oneWay.totalDistance.toStringAsFixed(1)} km\n');

  // 3. Your own costs, e.g. driving minutes from a distance-matrix API.
  //    Asymmetric matrices (one-way streets, traffic) are supported.
  const minutes = [
    [0, 12, 30, 25],
    [14, 0, 18, 22],
    [28, 20, 0, 9],
    [26, 21, 11, 0],
  ];
  final byTime = TspRouteFinder.solveMatrix(minutes);
  print('By time:    ${byTime.closedRoute}  '
      '(${byTime.totalDistance.toStringAsFixed(0)} min)\n');

  // 4. Compare with the old greedy algorithm.
  final greedy = TspRouteFinder.solve(
    stops,
    strategy: TspStrategy.nearestNeighbor,
  );
  final saved = greedy.totalDistance - roundTrip.totalDistance;
  print('Nearest neighbor would be ${greedy.totalDistance.toStringAsFixed(1)} '
      'km, ${saved.toStringAsFixed(1)} km longer.');

  // 5. Solve in the background so a Flutter UI stays smooth.
  final background = await TspRouteFinder.solveAsync(stops);
  print(
      '\nBackground solve: ${background.totalDistance.toStringAsFixed(1)} km');

  // 6. Several drivers with capacity, time windows and shifts.
  //    Times are minutes after 08:00.
  final plan = RoutePlanner.plan(
    depot: stops[0], // Cairo warehouse.
    stops: [
      for (final city in stops.skip(1))
        DeliveryStop(location: city, demand: 2, serviceTime: 15),
    ],
    vehicles: const [
      Vehicle(name: 'North', capacity: 8, shift: TimeWindow(0, 12 * 60)),
      Vehicle(name: 'South', capacity: 8, shift: TimeWindow(0, 24 * 60)),
    ],
    averageSpeedKmh: 80,
  );
  print('\nDelivery plan (${plan.totalDistance.toStringAsFixed(0)} km):');
  for (final route in plan.routes) {
    final cities = route.reorder(stops.skip(1).toList());
    print('  Vehicle ${route.vehicleIndex}: ${_names(cities)} '
        '(${route.distance.toStringAsFixed(0)} km, load ${route.load})');
  }
}

String _names(List<TspLocation> stops) => stops.map((s) => s.name).join(' -> ');

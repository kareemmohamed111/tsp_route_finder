// Run with: dart run example/main.dart
//
// In a Flutter app the same calls work unchanged, for example inside a
// button's onPressed callback. Use the result to reorder markers or draw a
// polyline on google_maps_flutter, flutter_map, etc.

import 'package:tsp_route_finder/tsp_route_finder.dart';

void main() {
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
}

String _names(List<TspLocation> stops) => stops.map((s) => s.name).join(' -> ');

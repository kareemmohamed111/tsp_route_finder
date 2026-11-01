/// Traveling Salesman Problem (TSP) solver for Dart and Flutter.
///
/// Give it a list of [TspLocation]s (or a distance matrix) and it returns the
/// order in which to visit them so the total distance is as short as
/// possible.
///
/// ```dart
/// import 'package:tsp_route_finder/tsp_route_finder.dart';
///
/// final result = TspRouteFinder.solve(const [
///   TspLocation(latitude: 30.0444, longitude: 31.2357, name: 'Cairo'),
///   TspLocation(latitude: 31.2001, longitude: 29.9187, name: 'Alexandria'),
///   TspLocation(latitude: 30.7865, longitude: 31.0004, name: 'Tanta'),
/// ]);
/// print(result.route); // [0, 2, 1]
/// ```
library;

export 'src/legacy.dart';
export 'src/location.dart';
export 'src/route_finder.dart';

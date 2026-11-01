// API kept for backwards compatibility with tsp_route_finder 0.0.3.

import 'dart:math' as math;

import 'location.dart';
import 'route_finder.dart';

/// Legacy entry point from version 0.0.3.
@Deprecated('Use TspRouteFinder.solve instead. Will be removed in 1.0.0.')
class TspPackage {
  /// Returns the visiting order of [locations] as a round trip starting at
  /// [startingLocationIndex].
  ///
  /// Since 0.1.0 this uses [TspStrategy.auto], so it returns optimal routes
  /// for small inputs and much shorter routes than before for larger ones.
  ///
  /// Throws an [ArgumentError] if [startingLocationIndex] is out of range.
  static Future<List<int>> calculateTspRoute({
    required List<TspLocation> locations,
    required int startingLocationIndex,
  }) async {
    if (startingLocationIndex < 0 ||
        startingLocationIndex >= locations.length) {
      throw ArgumentError('Invalid startingLocationIndex');
    }
    return TspRouteFinder.solve(
      locations,
      startIndex: startingLocationIndex,
    ).route;
  }
}

/// Legacy nearest-neighbor function from version 0.0.3.
///
/// Returns a new list on every call (0.0.3 reused a shared global list).
@Deprecated('Use TspRouteFinder.solve with TspStrategy.nearestNeighbor. '
    'Will be removed in 1.0.0.')
List<int> tspNearestNeighbor(
  List<TspLocation> locations,
  int startingLocationIndex,
) =>
    List.of(TspRouteFinder.solve(
      locations,
      startIndex: startingLocationIndex,
      strategy: TspStrategy.nearestNeighbor,
    ).route);

/// Legacy distance function from version 0.0.3. Returns kilometers.
@Deprecated('Use haversineDistance or TspLocation.distanceTo. '
    'Will be removed in 1.0.0.')
double calculateDistance(TspLocation location1, TspLocation location2) =>
    haversineDistance(location1, location2);

/// Legacy helper from version 0.0.3 that converts degrees to radians.
@Deprecated('Will be removed in 1.0.0.')
double radians(double degrees) => degrees * math.pi / 180;

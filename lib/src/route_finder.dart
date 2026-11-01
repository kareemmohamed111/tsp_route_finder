import 'dart:typed_data';

import 'algorithms.dart';
import 'background.dart';
import 'location.dart';

/// Signature of a function that returns the travel cost from [from] to [to].
///
/// The cost can be any non-negative unit: kilometers, meters, seconds, money.
/// It does not need to be symmetric.
typedef DistanceFunction = double Function(TspLocation from, TspLocation to);

/// The algorithm used to build a route.
enum TspStrategy {
  /// Uses [exact] for up to [TspRouteFinder.autoExactThreshold] stops and
  /// [optimized] for larger inputs. This is the recommended default.
  auto,

  /// Greedy nearest-neighbor heuristic: always go to the closest unvisited
  /// stop. Fastest, but routes are typically 15–25% longer than optimal.
  ///
  /// This is the algorithm used by versions 0.0.x of this package.
  nearestNeighbor,

  /// Nearest neighbor followed by 2-opt and Or-opt local search.
  ///
  /// Typically within a few percent of optimal and handles thousands of stops.
  optimized,

  /// Held–Karp dynamic programming. Always returns the shortest possible
  /// route, but cost grows exponentially, so it is limited to
  /// [TspRouteFinder.maxExactSize] stops.
  exact,
}

/// The outcome of a [TspRouteFinder] call.
class TspResult {
  /// Creates a result. Usually you get one from [TspRouteFinder] instead.
  const TspResult({
    required this.route,
    required this.totalDistance,
    required this.returnsToStart,
    required this.isOptimal,
    required this.strategy,
  });

  /// Indices into the input list, in visiting order.
  ///
  /// The first element is always the start index. For round trips the start
  /// is **not** repeated at the end; use [closedRoute] if you need that.
  final List<int> route;

  /// Total cost of the route, including the return leg for round trips.
  ///
  /// Measured in kilometers when using the default haversine distance, or in
  /// the units of your matrix / [DistanceFunction] otherwise.
  final double totalDistance;

  /// Whether the route returns to the start.
  final bool returnsToStart;

  /// Whether the route is guaranteed to be the shortest possible one.
  final bool isOptimal;

  /// The strategy that actually produced the route. Never [TspStrategy.auto].
  final TspStrategy strategy;

  /// [route] with the start index appended again for round trips, which is
  /// convenient for drawing a polyline.
  List<int> get closedRoute =>
      returnsToStart && route.length > 1 ? [...route, route.first] : route;

  /// Reorders [items] (for example your original stops, markers or customer
  /// objects) according to [route].
  ///
  /// ```dart
  /// final orderedStops = result.reorder(stops);
  /// ```
  List<T> reorder<T>(List<T> items) => [for (final i in route) items[i]];

  @override
  String toString() => 'TspResult(route: $route, '
      'totalDistance: ${totalDistance.toStringAsFixed(3)}, '
      'returnsToStart: $returnsToStart, isOptimal: $isOptimal, '
      'strategy: ${strategy.name})';
}

/// Solves the Traveling Salesman Problem for a list of locations or a
/// distance matrix.
///
/// ```dart
/// final result = TspRouteFinder.solve(stops, startIndex: 0);
/// print(result.route);          // e.g. [0, 4, 1, 2, 3]
/// print(result.totalDistance);  // kilometers
/// ```
///
/// [solve] and [solveMatrix] are synchronous. For large inputs in a Flutter
/// app, use [solveAsync] or [solveMatrixAsync] to keep the UI responsive.
abstract final class TspRouteFinder {
  /// Largest number of stops accepted by [TspStrategy.exact].
  static const int maxExactSize = 16;

  /// Largest number of stops for which [TspStrategy.auto] picks the exact
  /// solver. Above this size it uses [TspStrategy.optimized].
  static const int autoExactThreshold = 12;

  /// Finds a short route through [locations].
  ///
  /// * [startIndex]: index of the first stop (for example the depot or the
  ///   user's current position).
  /// * [returnToStart]: `true` (default) for a round trip that ends where it
  ///   started; `false` for a one-way path that ends at any stop.
  /// * [endIndex]: force a specific last stop. Requires
  ///   `returnToStart: false`.
  /// * [strategy]: which algorithm to use; see [TspStrategy].
  /// * [distance]: custom cost function. Defaults to [haversineDistance]
  ///   (great-circle kilometers).
  /// * [timeLimit]: optional cap on local-search time for
  ///   [TspStrategy.optimized]. The best route found so far is returned.
  ///
  /// Throws an [ArgumentError] if an index is out of range or the options
  /// conflict.
  static TspResult solve(
    List<TspLocation> locations, {
    int startIndex = 0,
    int? endIndex,
    bool returnToStart = true,
    TspStrategy strategy = TspStrategy.auto,
    DistanceFunction distance = haversineDistance,
    Duration? timeLimit,
  }) {
    final n = locations.length;
    final dist = Float64List(n * n);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (i == j) continue;
        final value = distance(locations[i], locations[j]);
        _checkCost(value, i, j);
        dist[i * n + j] = value;
      }
    }
    return _solve(
        n, dist, startIndex, endIndex, returnToStart, strategy, timeLimit);
  }

  /// Finds a short route given a precomputed [matrix], where `matrix[i][j]`
  /// is the cost of traveling from stop `i` to stop `j`.
  ///
  /// Use this with real road distances or travel times, for example from
  /// the Google Distance Matrix API or OSRM. The matrix may be asymmetric
  /// (one-way streets, traffic). Diagonal entries are ignored.
  ///
  /// The other parameters behave as in [solve].
  static TspResult solveMatrix(
    List<List<num>> matrix, {
    int startIndex = 0,
    int? endIndex,
    bool returnToStart = true,
    TspStrategy strategy = TspStrategy.auto,
    Duration? timeLimit,
  }) {
    final n = matrix.length;
    final dist = Float64List(n * n);
    for (var i = 0; i < n; i++) {
      final row = matrix[i];
      if (row.length != n) {
        throw ArgumentError.value(matrix, 'matrix',
            'Must be square: row $i has ${row.length} entries, expected $n');
      }
      for (var j = 0; j < n; j++) {
        if (i == j) continue;
        final value = row[j].toDouble();
        _checkCost(value, i, j);
        dist[i * n + j] = value;
      }
    }
    return _solve(
        n, dist, startIndex, endIndex, returnToStart, strategy, timeLimit);
  }

  /// Like [solve], but runs on a background isolate so a Flutter UI stays
  /// responsive while large inputs are being solved.
  ///
  /// On the web, where isolates are not available, the work runs
  /// asynchronously on the main thread instead.
  ///
  /// A custom [distance] must be a top-level or static function, or a closure
  /// that only captures sendable data (numbers, strings, lists, maps), because
  /// it is copied to the background isolate.
  static Future<TspResult> solveAsync(
    List<TspLocation> locations, {
    int startIndex = 0,
    int? endIndex,
    bool returnToStart = true,
    TspStrategy strategy = TspStrategy.auto,
    DistanceFunction distance = haversineDistance,
    Duration? timeLimit,
  }) {
    final copy = List<TspLocation>.of(locations);
    return runInBackground(() => solve(
          copy,
          startIndex: startIndex,
          endIndex: endIndex,
          returnToStart: returnToStart,
          strategy: strategy,
          distance: distance,
          timeLimit: timeLimit,
        ));
  }

  /// Like [solveMatrix], but runs on a background isolate. See [solveAsync].
  static Future<TspResult> solveMatrixAsync(
    List<List<num>> matrix, {
    int startIndex = 0,
    int? endIndex,
    bool returnToStart = true,
    TspStrategy strategy = TspStrategy.auto,
    Duration? timeLimit,
  }) {
    final copy = [for (final row in matrix) List<num>.of(row)];
    return runInBackground(() => solveMatrix(
          copy,
          startIndex: startIndex,
          endIndex: endIndex,
          returnToStart: returnToStart,
          strategy: strategy,
          timeLimit: timeLimit,
        ));
  }

  /// Total cost of visiting [locations] in the given [route] order, using
  /// [distance] (haversine kilometers by default).
  ///
  /// Handy for comparing a user-defined order with an optimized one.
  static double routeDistance(
    List<TspLocation> locations,
    List<int> route, {
    bool returnToStart = true,
    DistanceFunction distance = haversineDistance,
  }) {
    var total = 0.0;
    for (var k = 0; k + 1 < route.length; k++) {
      total += distance(locations[route[k]], locations[route[k + 1]]);
    }
    if (returnToStart && route.length > 1) {
      total += distance(locations[route.last], locations[route.first]);
    }
    return total;
  }

  static void _checkCost(double value, int i, int j) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError(
          'Distance from $i to $j must be finite and non-negative, got $value');
    }
  }

  static TspResult _solve(
    int n,
    Float64List dist,
    int startIndex,
    int? endIndex,
    bool returnToStart,
    TspStrategy strategy,
    Duration? timeLimit,
  ) {
    if (n == 0) {
      return TspResult(
        route: const [],
        totalDistance: 0,
        returnsToStart: returnToStart,
        isOptimal: true,
        strategy: strategy == TspStrategy.auto ? TspStrategy.exact : strategy,
      );
    }
    RangeError.checkValueInInterval(startIndex, 0, n - 1, 'startIndex');
    if (endIndex != null) {
      RangeError.checkValueInInterval(endIndex, 0, n - 1, 'endIndex');
      if (returnToStart) {
        throw ArgumentError('endIndex cannot be used with returnToStart: true. '
            'Pass returnToStart: false for a one-way route.');
      }
      if (endIndex == startIndex && n > 1) {
        throw ArgumentError(
            'endIndex must differ from startIndex. For a round trip use '
            'returnToStart: true instead.');
      }
    }
    if (strategy == TspStrategy.exact && n > maxExactSize) {
      throw ArgumentError(
          'TspStrategy.exact supports at most $maxExactSize stops, got $n. '
          'Use TspStrategy.optimized instead.');
    }

    final problem = Problem(
      n: n,
      dist: dist,
      start: startIndex,
      end: n > 1 ? endIndex : null,
      closed: returnToStart,
    );

    var used = strategy;
    if (used == TspStrategy.auto) {
      used =
          n <= autoExactThreshold ? TspStrategy.exact : TspStrategy.optimized;
    }

    final List<int> route;
    switch (used) {
      case TspStrategy.exact:
        route = heldKarp(problem);
      case TspStrategy.nearestNeighbor:
        route = nearestNeighbor(problem);
      case TspStrategy.optimized:
      case TspStrategy.auto:
        route = nearestNeighbor(problem);
        localSearch(
          problem,
          route,
          clock: timeLimit == null ? null : (Stopwatch()..start()),
          deadline: timeLimit,
        );
    }

    return TspResult(
      route: List.unmodifiable(route),
      totalDistance: problem.cost(route),
      returnsToStart: returnToStart,
      // Every ordering is optimal for up to 3 stops on a symmetric round trip,
      // and for up to 2 stops in general.
      isOptimal: used == TspStrategy.exact ||
          n <= 2 ||
          (n == 3 && returnToStart && problem.symmetric),
      strategy: used,
    );
  }
}

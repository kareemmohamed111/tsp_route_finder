import 'dart:typed_data';

import 'background.dart';
import 'location.dart';
import 'route_finder.dart';
import 'vrp_engine.dart';

/// Signature of a function that returns the travel time from [from] to [to],
/// in minutes (or whatever time unit you use consistently).
typedef TravelTimeFunction = double Function(TspLocation from, TspLocation to);

/// A time interval `[earliest, latest]`.
///
/// Times are plain numbers in the same unit as travel times: minutes by
/// default. Choose any zero point you like, for example `0` = 08:00, so
/// `TimeWindow(60, 120)` means 09:00–10:00.
class TimeWindow {
  /// Creates a window from [earliest] to [latest] (inclusive).
  const TimeWindow(this.earliest, this.latest)
      : assert(earliest <= latest, 'earliest must not be after latest');

  /// No constraint: from `0` to infinity.
  static const TimeWindow unlimited = TimeWindow(0, double.infinity);

  /// Earliest allowed time. Vehicles that arrive earlier wait.
  final double earliest;

  /// Latest allowed time.
  final double latest;

  /// Whether [time] is inside this window.
  bool contains(double time) => time >= earliest && time <= latest;

  @override
  bool operator ==(Object other) =>
      other is TimeWindow &&
      other.earliest == earliest &&
      other.latest == latest;

  @override
  int get hashCode => Object.hash(earliest, latest);

  @override
  String toString() => 'TimeWindow($earliest, $latest)';
}

/// A place a vehicle must visit, with optional delivery constraints.
class DeliveryStop {
  /// Creates a stop at [location].
  const DeliveryStop({
    required this.location,
    this.demand = 0,
    this.serviceTime = 0,
    this.timeWindow,
  });

  /// Where the stop is.
  final TspLocation location;

  /// How much vehicle capacity the stop uses: parcels, kilograms, seats…
  /// Compared against [Vehicle.capacity].
  final double demand;

  /// Time spent at the stop (unloading, paperwork), in minutes.
  final double serviceTime;

  /// When service at this stop may **start**. `null` means any time.
  final TimeWindow? timeWindow;

  @override
  String toString() => 'DeliveryStop(${location.name ?? location}, '
      'demand: $demand, serviceTime: $serviceTime, timeWindow: $timeWindow)';
}

/// A vehicle or driver that can serve [DeliveryStop]s.
class Vehicle {
  /// Creates a vehicle. Every parameter is optional.
  const Vehicle({
    this.name,
    this.capacity = double.infinity,
    this.start,
    this.end,
    this.returnToStart = true,
    this.shift,
    this.maxStops,
  });

  /// Optional label, for example the driver's name.
  final String? name;

  /// Maximum total [DeliveryStop.demand] this vehicle can carry.
  final double capacity;

  /// Where the vehicle starts. Defaults to the planner's `depot`.
  final TspLocation? start;

  /// Where the vehicle must finish, for example the driver's home.
  /// If `null`, the vehicle returns to [start] when [returnToStart] is
  /// `true`, or finishes at its last stop otherwise.
  final TspLocation? end;

  /// Whether the vehicle returns to [start] when no [end] is given.
  final bool returnToStart;

  /// Working hours. The vehicle leaves at `shift.earliest` and must be done
  /// (back at its end, or finished at its last stop) by `shift.latest`.
  final TimeWindow? shift;

  /// Maximum number of stops this vehicle may visit.
  final int? maxStops;

  @override
  String toString() => 'Vehicle(${name ?? ''})';
}

/// The stops assigned to one vehicle, in visiting order, with a schedule.
class VehicleRoute {
  /// Creates a route. Usually you get one from [RoutePlanner] instead.
  const VehicleRoute({
    required this.vehicleIndex,
    required this.stops,
    required this.arrivalTimes,
    required this.serviceStartTimes,
    required this.startTime,
    required this.endTime,
    required this.distance,
    required this.travelTime,
    required this.load,
  });

  /// Index of the vehicle in the list passed to [RoutePlanner.plan].
  final int vehicleIndex;

  /// Indices into the `stops` list, in visiting order.
  final List<int> stops;

  /// When the vehicle arrives at each stop in [stops].
  final List<double> arrivalTimes;

  /// When service starts at each stop: the arrival time, or later if the
  /// vehicle has to wait for the stop's time window to open.
  final List<double> serviceStartTimes;

  /// When the vehicle leaves its start location.
  final double startTime;

  /// When the vehicle reaches its end location, or finishes its last stop
  /// for one-way routes.
  final double endTime;

  /// Total distance driven, including the legs from the start and to the
  /// end location.
  final double distance;

  /// Total driving time, excluding waiting and service time.
  final double travelTime;

  /// Total demand delivered on this route.
  final double load;

  /// Whether this vehicle has no stops (it is not needed).
  bool get isEmpty => stops.isEmpty;

  /// Reorders [items] (for example your original stop objects) according to
  /// [stops].
  List<T> reorder<T>(List<T> items) => [for (final i in stops) items[i]];

  @override
  String toString() => 'VehicleRoute(vehicle: $vehicleIndex, stops: $stops, '
      'distance: ${distance.toStringAsFixed(2)}, load: $load)';
}

/// The result of [RoutePlanner.plan].
class RoutePlan {
  /// Creates a plan. Usually you get one from [RoutePlanner] instead.
  const RoutePlan({required this.routes, required this.unassigned});

  /// One route per vehicle, in the same order as the vehicles you passed.
  /// Vehicles that are not needed get an empty route.
  final List<VehicleRoute> routes;

  /// Indices of stops that could not be served by any vehicle without
  /// breaking a constraint (capacity, time window, shift, max stops).
  final List<int> unassigned;

  /// Whether every stop was assigned to a vehicle.
  bool get isComplete => unassigned.isEmpty;

  /// Total distance driven by all vehicles.
  double get totalDistance =>
      routes.fold(0.0, (sum, route) => sum + route.distance);

  /// Total driving time of all vehicles.
  double get totalTravelTime =>
      routes.fold(0.0, (sum, route) => sum + route.travelTime);

  /// Number of vehicles with at least one stop.
  int get usedVehicleCount => routes.where((r) => !r.isEmpty).length;

  @override
  String toString() => 'RoutePlan(routes: $routes, unassigned: $unassigned, '
      'totalDistance: ${totalDistance.toStringAsFixed(2)})';
}

/// Plans delivery routes for one or more vehicles: a Vehicle Routing Problem
/// with capacities, time windows, service times and shifts.
///
/// ```dart
/// final plan = RoutePlanner.plan(
///   depot: warehouse,
///   stops: [
///     DeliveryStop(location: a, demand: 3),
///     DeliveryStop(location: b, demand: 5, timeWindow: TimeWindow(60, 120)),
///     DeliveryStop(location: c, demand: 2, serviceTime: 10),
///   ],
///   vehicles: const [Vehicle(name: 'Ali', capacity: 8), Vehicle(name: 'Sara', capacity: 8)],
/// );
/// for (final route in plan.routes) {
///   print('${route.vehicleIndex}: ${route.stops}');
/// }
/// ```
///
/// The planner first builds routes with regret insertion, then improves
/// them with relocate, swap, 2-opt and 2-opt* moves while keeping every
/// constraint satisfied. It minimizes total distance.
abstract final class RoutePlanner {
  /// Assigns [stops] to [vehicles] and orders each vehicle's route.
  ///
  /// * [depot]: default start (and end) for vehicles without their own
  ///   [Vehicle.start]. Required unless every vehicle sets `start`.
  /// * [distance]: cost function minimized by the planner. Defaults to
  ///   [haversineDistance] (kilometers).
  /// * [travelTime]: driving time between two locations, in minutes. Defaults
  ///   to `distance / averageSpeedKmh * 60`.
  /// * [averageSpeedKmh]: used by the default [travelTime].
  /// * [balance]: spread stops evenly, so no vehicle visits more than
  ///   `ceil(stops / vehicles)` stops. Without it the planner only minimizes
  ///   distance, which may leave some vehicles unused when nothing else
  ///   (capacity, time windows, shifts) forces a split.
  /// * [timeLimit]: optional cap on optimization time.
  ///
  /// Stops that cannot be served are returned in [RoutePlan.unassigned]
  /// instead of throwing.
  static RoutePlan plan({
    required List<DeliveryStop> stops,
    required List<Vehicle> vehicles,
    TspLocation? depot,
    DistanceFunction distance = haversineDistance,
    TravelTimeFunction? travelTime,
    double averageSpeedKmh = 40,
    bool balance = false,
    Duration? timeLimit,
  }) {
    if (vehicles.isEmpty) {
      throw ArgumentError.value(vehicles, 'vehicles', 'Must not be empty');
    }
    if (!(averageSpeedKmh > 0) || !averageSpeedKmh.isFinite) {
      throw ArgumentError.value(
          averageSpeedKmh, 'averageSpeedKmh', 'Must be positive');
    }
    for (var i = 0; i < stops.length; i++) {
      final s = stops[i];
      if (!(s.demand >= 0) || !s.demand.isFinite) {
        throw ArgumentError('stops[$i].demand must be finite and >= 0');
      }
      if (!(s.serviceTime >= 0) || !s.serviceTime.isFinite) {
        throw ArgumentError('stops[$i].serviceTime must be finite and >= 0');
      }
    }

    final s = stops.length;
    final v = vehicles.length;
    // Node layout: stops 0..s-1, then a start and an end node per vehicle.
    final nodes = <TspLocation>[for (final stop in stops) stop.location];
    final startNode = Int32List(v);
    final endNode = Int32List(v);
    for (var k = 0; k < v; k++) {
      final vehicle = vehicles[k];
      final start = vehicle.start ?? depot;
      if (start == null) {
        throw ArgumentError(
            'vehicles[$k] has no start location and no depot was given.');
      }
      if (vehicle.capacity < 0 || vehicle.capacity.isNaN) {
        throw ArgumentError('vehicles[$k].capacity must be >= 0');
      }
      if (vehicle.maxStops != null && vehicle.maxStops! < 0) {
        throw ArgumentError('vehicles[$k].maxStops must be >= 0');
      }
      startNode[k] = nodes.length;
      nodes.add(start);
      final end = vehicle.end ?? (vehicle.returnToStart ? start : null);
      if (end == null) {
        endNode[k] = -1;
      } else {
        endNode[k] = nodes.length;
        nodes.add(end);
      }
    }

    final n = nodes.length;
    final dist = Float64List(n * n);
    final time = Float64List(n * n);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (i == j) continue;
        final d = distance(nodes[i], nodes[j]);
        final t = travelTime != null
            ? travelTime(nodes[i], nodes[j])
            : d / averageSpeedKmh * 60;
        if (!d.isFinite || d < 0 || !t.isFinite || t < 0) {
          throw ArgumentError('Distance and travel time between '
              '${nodes[i]} and ${nodes[j]} must be finite and >= 0');
        }
        dist[i * n + j] = d;
        time[i * n + j] = t;
      }
    }

    final balancedMax = s == 0 ? 0 : (s + v - 1) ~/ v;
    final problem = VrpProblem(
      stopCount: s,
      vehicleCount: v,
      n: n,
      dist: dist,
      time: time,
      demand: Float64List.fromList([for (final x in stops) x.demand]),
      service: Float64List.fromList([for (final x in stops) x.serviceTime]),
      twEarliest: Float64List.fromList(
          [for (final x in stops) x.timeWindow?.earliest ?? 0]),
      twLatest: Float64List.fromList(
          [for (final x in stops) x.timeWindow?.latest ?? double.infinity]),
      startNode: startNode,
      endNode: endNode,
      capacity: Float64List.fromList([for (final x in vehicles) x.capacity]),
      shiftStart: Float64List.fromList(
          [for (final x in vehicles) x.shift?.earliest ?? 0]),
      shiftEnd: Float64List.fromList(
          [for (final x in vehicles) x.shift?.latest ?? double.infinity]),
      maxStops: Int32List.fromList([
        for (final x in vehicles)
          _minStops(x.maxStops, balance ? balancedMax : null),
      ]),
    );

    final solution = solveVrp(problem, timeLimit: timeLimit);

    return RoutePlan(
      routes: [
        for (var k = 0; k < v; k++) _buildRoute(problem, k, solution[k]),
      ],
      unassigned: List.unmodifiable(solution.unassigned..sort()),
    );
  }

  /// Like [plan], but runs on a background isolate so a Flutter UI stays
  /// responsive. On the web it runs asynchronously on the main thread.
  ///
  /// Custom [distance] and [travelTime] functions must be top-level or static
  /// functions, or closures that only capture sendable data.
  static Future<RoutePlan> planAsync({
    required List<DeliveryStop> stops,
    required List<Vehicle> vehicles,
    TspLocation? depot,
    DistanceFunction distance = haversineDistance,
    TravelTimeFunction? travelTime,
    double averageSpeedKmh = 40,
    bool balance = false,
    Duration? timeLimit,
  }) {
    final stopsCopy = List<DeliveryStop>.of(stops);
    final vehiclesCopy = List<Vehicle>.of(vehicles);
    return runInBackground(() => plan(
          stops: stopsCopy,
          vehicles: vehiclesCopy,
          depot: depot,
          distance: distance,
          travelTime: travelTime,
          averageSpeedKmh: averageSpeedKmh,
          balance: balance,
          timeLimit: timeLimit,
        ));
  }

  static int _minStops(int? a, int? b) {
    const unlimited = 0x3fffffff;
    return [a ?? unlimited, b ?? unlimited].reduce((x, y) => x < y ? x : y);
  }

  static VehicleRoute _buildRoute(VrpProblem p, int v, List<int> stops) {
    if (stops.isEmpty) {
      // Unused vehicle: it does not drive at all.
      return VehicleRoute(
        vehicleIndex: v,
        stops: const [],
        arrivalTimes: const [],
        serviceStartTimes: const [],
        startTime: p.shiftStart[v],
        endTime: p.shiftStart[v],
        distance: 0,
        travelTime: 0,
        load: 0,
      );
    }
    final arrivals = <double>[];
    final starts = <double>[];
    var t = p.shiftStart[v];
    var prev = p.startNode[v];
    var dist = 0.0;
    var travel = 0.0;
    var load = 0.0;
    for (final u in stops) {
      dist += p.d(prev, u);
      travel += p.t(prev, u);
      t += p.t(prev, u);
      arrivals.add(t);
      if (t < p.twEarliest[u]) t = p.twEarliest[u];
      starts.add(t);
      t += p.service[u];
      load += p.demand[u];
      prev = u;
    }
    final end = p.endNode[v];
    if (end >= 0) {
      dist += p.d(prev, end);
      travel += p.t(prev, end);
      t += p.t(prev, end);
    }
    return VehicleRoute(
      vehicleIndex: v,
      stops: List.unmodifiable(stops),
      arrivalTimes: List.unmodifiable(arrivals),
      serviceStartTimes: List.unmodifiable(starts),
      startTime: p.shiftStart[v],
      endTime: t,
      distance: dist,
      travelTime: travel,
      load: load,
    );
  }
}

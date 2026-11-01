// Internal Vehicle Routing Problem engine. Not part of the public API.
//
// Construction: regret-2 insertion with O(1) time-window feasibility checks.
// Improvement: intra-route 2-opt, relocate, swap and 2-opt* local search,
// accepting only moves that shorten the total distance and keep every route
// feasible (capacity, time windows, shift, max stops).

import 'dart:typed_data';

const double _eps = 1e-9;

/// A fully-specified VRP instance. Nodes `0..stopCount-1` are stops; the
/// remaining nodes are vehicle start / end locations.
class VrpProblem {
  /// Creates a problem. Matrices are row-major `n * n`.
  VrpProblem({
    required this.stopCount,
    required this.vehicleCount,
    required this.n,
    required this.dist,
    required this.time,
    required this.demand,
    required this.service,
    required this.twEarliest,
    required this.twLatest,
    required this.startNode,
    required this.endNode,
    required this.capacity,
    required this.shiftStart,
    required this.shiftEnd,
    required this.maxStops,
  });

  /// Number of stops.
  final int stopCount;

  /// Number of vehicles.
  final int vehicleCount;

  /// Number of nodes (stops plus vehicle start / end nodes).
  final int n;

  /// Distance matrix, minimized by the solver.
  final Float64List dist;

  /// Travel-time matrix, used for time windows and shifts.
  final Float64List time;

  /// Demand of each stop.
  final Float64List demand;

  /// Service time of each stop.
  final Float64List service;

  /// Earliest service start of each stop.
  final Float64List twEarliest;

  /// Latest service start of each stop.
  final Float64List twLatest;

  /// Start node of each vehicle.
  final Int32List startNode;

  /// End node of each vehicle, or -1 for open routes.
  final Int32List endNode;

  /// Capacity of each vehicle.
  final Float64List capacity;

  /// Departure time of each vehicle.
  final Float64List shiftStart;

  /// Time by which each vehicle must be done.
  final Float64List shiftEnd;

  /// Maximum number of stops of each vehicle.
  final Int32List maxStops;

  /// Distance `a -> b`.
  double d(int a, int b) => dist[a * n + b];

  /// Travel time `a -> b`.
  double t(int a, int b) => time[a * n + b];

  /// Distance `a -> b`, where `b == -1` (no end node) costs nothing.
  double e(int a, int b) => b < 0 ? 0.0 : dist[a * n + b];
}

/// Routes per vehicle plus the stops that could not be served.
class VrpSolution {
  /// Creates a solution.
  VrpSolution(this.routes, this.unassigned);

  /// Stop indices per vehicle, in visiting order.
  final List<List<int>> routes;

  /// Stops that no vehicle can serve.
  final List<int> unassigned;

  /// The route of vehicle [v].
  List<int> operator [](int v) => routes[v];
}

/// Solves [p], stopping local search when [timeLimit] expires.
VrpSolution solveVrp(VrpProblem p, {Duration? timeLimit}) {
  final solver = _VrpSolver(p, timeLimit);
  solver.construct();
  solver.improve();
  return VrpSolution(solver.routes, solver.unassigned);
}

class _VrpSolver {
  _VrpSolver(this.p, this.limit)
      : routes = List.generate(p.vehicleCount, (_) => <int>[]),
        load = Float64List(p.vehicleCount),
        depart = List.generate(p.vehicleCount, (_) => Float64List(0)),
        latest = List.generate(p.vehicleCount, (_) => Float64List(0)),
        symmetric = _isSymmetric(p),
        clock = Stopwatch()..start();

  final VrpProblem p;
  final Duration? limit;
  final Stopwatch clock;
  final bool symmetric;

  final List<List<int>> routes;
  final Float64List load;
  List<int> unassigned = [];

  /// Per route: time the vehicle leaves each stop.
  final List<Float64List> depart;

  /// Per route: latest service start at each stop that keeps the rest of
  /// the route feasible.
  final List<Float64List> latest;

  bool get timedOut => limit != null && clock.elapsed >= limit!;

  static bool _isSymmetric(VrpProblem p) {
    for (var i = 0; i < p.n; i++) {
      for (var j = i + 1; j < p.n; j++) {
        if ((p.d(i, j) - p.d(j, i)).abs() > _eps) return false;
      }
    }
    return true;
  }

  int _start(int v) => p.startNode[v];
  int _end(int v) => p.endNode[v];

  /// Cost of an empty route, which is treated as "vehicle not used" (0).
  double _emptyCost(int v) => p.e(_start(v), _end(v));

  // ---------------------------------------------------------------- checks

  bool _feasible(int v, List<int> r) {
    if (r.isEmpty) return true;
    if (r.length > p.maxStops[v]) return false;
    var l = 0.0;
    for (final u in r) {
      l += p.demand[u];
    }
    if (l > p.capacity[v] + _eps) return false;
    var t = p.shiftStart[v];
    var prev = _start(v);
    for (final u in r) {
      t += p.t(prev, u);
      if (t < p.twEarliest[u]) t = p.twEarliest[u];
      if (t > p.twLatest[u] + _eps) return false;
      t += p.service[u];
      prev = u;
    }
    final end = _end(v);
    if (end >= 0) t += p.t(prev, end);
    return t <= p.shiftEnd[v] + _eps;
  }

  double _loadOf(List<int> r) {
    var l = 0.0;
    for (final u in r) {
      l += p.demand[u];
    }
    return l;
  }

  void _setRoute(int v, List<int> r) {
    routes[v] = r;
    load[v] = _loadOf(r);
  }

  // ---------------------------------------------------------- construction

  void _refreshSchedule(int v) {
    final r = routes[v];
    final m = r.length;
    final dep = Float64List(m);
    final lat = Float64List(m);
    var t = p.shiftStart[v];
    var prev = _start(v);
    for (var k = 0; k < m; k++) {
      final u = r[k];
      t += p.t(prev, u);
      if (t < p.twEarliest[u]) t = p.twEarliest[u];
      t += p.service[u];
      dep[k] = t;
      prev = u;
    }
    if (m > 0) {
      final last = r[m - 1];
      final end = _end(v);
      final finishBy =
          end >= 0 ? p.shiftEnd[v] - p.t(last, end) : p.shiftEnd[v];
      var bound = finishBy - p.service[last];
      lat[m - 1] = bound < p.twLatest[last] ? bound : p.twLatest[last];
      for (var k = m - 2; k >= 0; k--) {
        final u = r[k];
        bound = lat[k + 1] - p.t(u, r[k + 1]) - p.service[u];
        lat[k] = bound < p.twLatest[u] ? bound : p.twLatest[u];
      }
    }
    depart[v] = dep;
    latest[v] = lat;
  }

  /// Cheapest feasible insertion of stop [u] into route [v], using the
  /// cached schedule. Returns (cost, position) or (infinity, -1).
  (double, int) _bestInsertion(int u, int v) {
    final r = routes[v];
    final m = r.length;
    if (m + 1 > p.maxStops[v]) return (double.infinity, -1);
    if (load[v] + p.demand[u] > p.capacity[v] + _eps) {
      return (double.infinity, -1);
    }
    final dep = depart[v];
    final lat = latest[v];
    final end = _end(v);
    var best = double.infinity;
    var bestPos = -1;
    for (var k = 0; k <= m; k++) {
      final prev = k == 0 ? _start(v) : r[k - 1];
      final leavePrev = k == 0 ? p.shiftStart[v] : dep[k - 1];
      var startU = leavePrev + p.t(prev, u);
      if (startU < p.twEarliest[u]) startU = p.twEarliest[u];
      if (startU > p.twLatest[u] + _eps) continue;
      final leaveU = startU + p.service[u];
      double cost;
      if (k < m) {
        final next = r[k];
        var startNext = leaveU + p.t(u, next);
        if (startNext < p.twEarliest[next]) startNext = p.twEarliest[next];
        if (startNext > lat[k] + _eps) continue;
        cost = p.d(prev, u) + p.d(u, next) - p.d(prev, next);
      } else {
        final finish = end >= 0 ? leaveU + p.t(u, end) : leaveU;
        if (finish > p.shiftEnd[v] + _eps) continue;
        cost = p.d(prev, u) + p.e(u, end) - p.e(prev, end);
        if (m == 0) cost += _emptyCost(v);
      }
      if (cost < best) {
        best = cost;
        bestPos = k;
      }
    }
    return (best, bestPos);
  }

  void construct() {
    final vCount = p.vehicleCount;
    final sCount = p.stopCount;
    for (var v = 0; v < vCount; v++) {
      _refreshSchedule(v);
    }
    final remaining = <int>{for (var u = 0; u < sCount; u++) u};
    final cost = Float64List(sCount * vCount);
    final pos = Int32List(sCount * vCount);
    for (final u in remaining) {
      for (var v = 0; v < vCount; v++) {
        final (c, k) = _bestInsertion(u, v);
        cost[u * vCount + v] = c;
        pos[u * vCount + v] = k;
      }
    }

    const mustInsertNow = 1e300;
    while (remaining.isNotEmpty) {
      var pick = -1;
      var pickRegret = double.negativeInfinity;
      var pickBest = 0.0;
      var pickVehicle = -1;
      for (final u in remaining) {
        var c1 = double.infinity, c2 = double.infinity;
        var v1 = -1;
        for (var v = 0; v < vCount; v++) {
          final c = cost[u * vCount + v];
          if (c < c1) {
            c2 = c1;
            c1 = c;
            v1 = v;
          } else if (c < c2) {
            c2 = c;
          }
        }
        if (v1 < 0) continue;
        final regret = c2 == double.infinity ? mustInsertNow : c2 - c1;
        // Highest regret first; on ties the most expensive (farthest) stop.
        if (regret > pickRegret + _eps ||
            ((regret - pickRegret).abs() <= _eps && c1 > pickBest)) {
          pick = u;
          pickRegret = regret;
          pickBest = c1;
          pickVehicle = v1;
        }
      }
      if (pick < 0) break;

      final v = pickVehicle;
      routes[v].insert(pos[pick * vCount + v], pick);
      load[v] += p.demand[pick];
      remaining.remove(pick);
      _refreshSchedule(v);
      for (final u in remaining) {
        final (c, k) = _bestInsertion(u, v);
        cost[u * vCount + v] = c;
        pos[u * vCount + v] = k;
      }
    }
    unassigned = remaining.toList();
  }

  // ----------------------------------------------------------- improvement

  void improve() {
    var improved = true;
    while (improved && !timedOut) {
      improved = false;
      if (_intraTwoOpt()) improved = true;
      if (_relocate()) improved = true;
      if (_swap()) improved = true;
      if (_twoOptStar()) improved = true;
      if (_insertUnassigned()) improved = true;
    }
  }

  /// Reverses segments inside each route.
  bool _intraTwoOpt() {
    var changed = false;
    for (var v = 0; v < p.vehicleCount; v++) {
      var r = routes[v];
      final m = r.length;
      final end = _end(v);
      for (var i = 0; i < m - 1; i++) {
        if (timedOut) return changed;
        for (var j = i + 1; j < m; j++) {
          final prev = i == 0 ? _start(v) : r[i - 1];
          final next = j + 1 < m ? r[j + 1] : end;
          var delta = p.d(prev, r[j]) +
              p.e(r[i], next) -
              p.d(prev, r[i]) -
              p.e(r[j], next);
          if (!symmetric) {
            for (var k = i; k < j; k++) {
              delta += p.d(r[k + 1], r[k]) - p.d(r[k], r[k + 1]);
            }
          }
          if (delta >= -_eps) continue;
          final cand = [
            ...r.sublist(0, i),
            ...r.sublist(i, j + 1).reversed,
            ...r.sublist(j + 1),
          ];
          if (!_feasible(v, cand)) continue;
          routes[v] = cand;
          r = cand;
          changed = true;
        }
      }
    }
    return changed;
  }

  /// Moves single stops to a better position in any route.
  bool _relocate() {
    var changed = false;
    for (var a = 0; a < p.vehicleCount; a++) {
      var i = 0;
      while (i < routes[a].length) {
        if (timedOut) return changed;
        if (_tryRelocate(a, i)) {
          changed = true;
        } else {
          i++;
        }
      }
    }
    return changed;
  }

  bool _tryRelocate(int a, int i) {
    final rA = routes[a];
    final m = rA.length;
    final u = rA[i];
    final pA = i == 0 ? _start(a) : rA[i - 1];
    final nA = i + 1 < m ? rA[i + 1] : _end(a);
    var removeDelta = p.e(pA, nA) - p.d(pA, u) - p.e(u, nA);
    if (m == 1) removeDelta -= _emptyCost(a);
    final reduced = List<int>.of(rA)..removeAt(i);
    bool? reducedOk;

    for (var b = 0; b < p.vehicleCount; b++) {
      if (b != a) {
        if (routes[b].length + 1 > p.maxStops[b]) continue;
        if (load[b] + p.demand[u] > p.capacity[b] + _eps) continue;
      }
      final target = b == a ? reduced : routes[b];
      final mt = target.length;
      final end = _end(b);
      for (var k = 0; k <= mt; k++) {
        if (b == a && k == i) continue;
        final prev = k == 0 ? _start(b) : target[k - 1];
        final next = k < mt ? target[k] : end;
        var delta = removeDelta + p.d(prev, u) + p.e(u, next) - p.e(prev, next);
        if (mt == 0) delta += _emptyCost(b);
        if (delta >= -_eps) continue;
        final cand = List<int>.of(target)..insert(k, u);
        if (!_feasible(b, cand)) continue;
        if (b != a) {
          reducedOk ??= _feasible(a, reduced);
          if (!reducedOk) continue;
          _setRoute(a, reduced);
        }
        _setRoute(b, cand);
        return true;
      }
    }
    return false;
  }

  /// Exchanges two stops between different routes.
  bool _swap() {
    var changed = false;
    final vCount = p.vehicleCount;
    for (var a = 0; a < vCount; a++) {
      for (var b = a + 1; b < vCount; b++) {
        var rA = routes[a], rB = routes[b];
        for (var i = 0; i < rA.length; i++) {
          if (timedOut) return changed;
          for (var j = 0; j < rB.length; j++) {
            final u = rA[i], w = rB[j];
            final du = p.demand[u], dw = p.demand[w];
            if (load[a] - du + dw > p.capacity[a] + _eps) continue;
            if (load[b] - dw + du > p.capacity[b] + _eps) continue;
            final pA = i == 0 ? _start(a) : rA[i - 1];
            final nA = i + 1 < rA.length ? rA[i + 1] : _end(a);
            final pB = j == 0 ? _start(b) : rB[j - 1];
            final nB = j + 1 < rB.length ? rB[j + 1] : _end(b);
            final delta = p.d(pA, w) +
                p.e(w, nA) -
                p.d(pA, u) -
                p.e(u, nA) +
                p.d(pB, u) +
                p.e(u, nB) -
                p.d(pB, w) -
                p.e(w, nB);
            if (delta >= -_eps) continue;
            final candA = List<int>.of(rA)..[i] = w;
            final candB = List<int>.of(rB)..[j] = u;
            if (!_feasible(a, candA) || !_feasible(b, candB)) continue;
            _setRoute(a, candA);
            _setRoute(b, candB);
            rA = candA;
            rB = candB;
            changed = true;
          }
        }
      }
    }
    return changed;
  }

  /// Exchanges route tails between two vehicles.
  bool _twoOptStar() {
    var changed = false;
    for (var a = 0; a < p.vehicleCount; a++) {
      for (var b = a + 1; b < p.vehicleCount; b++) {
        while (_twoOptStarPair(a, b)) {
          changed = true;
          if (timedOut) return changed;
        }
        if (timedOut) return changed;
      }
    }
    return changed;
  }

  bool _twoOptStarPair(int a, int b) {
    final rA = routes[a], rB = routes[b];
    final mA = rA.length, mB = rB.length;
    if (mA == 0 && mB == 0) return false;
    final cumA = _prefixCost(a, rA), cumB = _prefixCost(b, rB);
    final ldA = _prefixLoad(rA), ldB = _prefixLoad(rB);
    final endA = _end(a), endB = _end(b);
    final oldCost = _routeCost(a, rA, cumA) + _routeCost(b, rB, cumB);

    for (var i = 0; i <= mA; i++) {
      final lastA = i == 0 ? _start(a) : rA[i - 1];
      for (var j = 0; j <= mB; j++) {
        if (i == mA && j == mB) continue;
        final lenA = i + (mB - j), lenB = j + (mA - i);
        if (lenA > p.maxStops[a] || lenB > p.maxStops[b]) continue;
        if (ldA[i] + ldB[mB] - ldB[j] > p.capacity[a] + _eps) continue;
        if (ldB[j] + ldA[mA] - ldA[i] > p.capacity[b] + _eps) continue;
        final lastB = j == 0 ? _start(b) : rB[j - 1];
        final newA =
            lenA == 0 ? 0.0 : cumA[i] + _tail(lastA, rB, j, cumB, endA);
        final newB =
            lenB == 0 ? 0.0 : cumB[j] + _tail(lastB, rA, i, cumA, endB);
        if (newA + newB - oldCost >= -_eps) continue;
        final candA = [...rA.sublist(0, i), ...rB.sublist(j)];
        final candB = [...rB.sublist(0, j), ...rA.sublist(i)];
        if (!_feasible(a, candA) || !_feasible(b, candB)) continue;
        _setRoute(a, candA);
        _setRoute(b, candB);
        return true;
      }
    }
    return false;
  }

  /// cum[k] = distance from the start node through the first k stops.
  Float64List _prefixCost(int v, List<int> r) {
    final cum = Float64List(r.length + 1);
    var prev = _start(v);
    for (var k = 0; k < r.length; k++) {
      cum[k + 1] = cum[k] + p.d(prev, r[k]);
      prev = r[k];
    }
    return cum;
  }

  Float64List _prefixLoad(List<int> r) {
    final ld = Float64List(r.length + 1);
    for (var k = 0; k < r.length; k++) {
      ld[k + 1] = ld[k] + p.demand[r[k]];
    }
    return ld;
  }

  double _routeCost(int v, List<int> r, Float64List cum) {
    if (r.isEmpty) return 0;
    return cum[r.length] + p.e(r.last, _end(v));
  }

  /// Cost of going from [last] through r[j..] to [end].
  double _tail(int last, List<int> r, int j, Float64List cum, int end) {
    final m = r.length;
    if (j >= m) return p.e(last, end);
    return p.d(last, r[j]) + (cum[m] - cum[j + 1]) + p.e(r[m - 1], end);
  }

  /// Tries again to place stops that could not be assigned.
  bool _insertUnassigned() {
    if (unassigned.isEmpty) return false;
    for (var v = 0; v < p.vehicleCount; v++) {
      _refreshSchedule(v);
    }
    var changed = false;
    for (final u in List<int>.of(unassigned)) {
      var best = double.infinity;
      var bestV = -1, bestK = -1;
      for (var v = 0; v < p.vehicleCount; v++) {
        final (c, k) = _bestInsertion(u, v);
        if (c < best) {
          best = c;
          bestV = v;
          bestK = k;
        }
      }
      if (bestV < 0) continue;
      routes[bestV].insert(bestK, u);
      load[bestV] += p.demand[u];
      _refreshSchedule(bestV);
      unassigned.remove(u);
      changed = true;
    }
    return changed;
  }
}

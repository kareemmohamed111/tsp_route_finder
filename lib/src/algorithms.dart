// Internal TSP algorithms. Not part of the public API.

import 'dart:typed_data';

/// Tolerance used when deciding whether a move is a strict improvement, so
/// floating-point noise cannot make local search loop forever.
const double _eps = 1e-9;

/// A fully-specified TSP instance over a dense distance matrix.
class Problem {
  /// Creates a problem; [dist] must hold `n * n` entries.
  Problem({
    required this.n,
    required this.dist,
    required this.start,
    required this.end,
    required this.closed,
  }) : symmetric = _isSymmetric(n, dist);

  /// Number of nodes.
  final int n;

  /// Row-major `n * n` distance matrix.
  final Float64List dist;

  /// Fixed first node of the route.
  final int start;

  /// Fixed last node of the route, or `null` if the end is free.
  final int? end;

  /// Whether the route returns from the last node back to [start].
  final bool closed;

  /// Whether `dist[i][j] == dist[j][i]` for all pairs.
  final bool symmetric;

  /// Cost of the edge `a -> b`.
  double d(int a, int b) => dist[a * n + b];

  /// Cost of the edge `a -> b`, where `b == -1` means "no successor".
  double e(int a, int b) => b < 0 ? 0.0 : dist[a * n + b];

  /// Total cost of [route], including the closing edge for closed tours.
  double cost(List<int> route) {
    var total = 0.0;
    for (var k = 0; k + 1 < route.length; k++) {
      total += d(route[k], route[k + 1]);
    }
    if (closed && route.length > 1) total += d(route.last, route.first);
    return total;
  }

  static bool _isSymmetric(int n, Float64List dist) {
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        if ((dist[i * n + j] - dist[j * n + i]).abs() > _eps) return false;
      }
    }
    return true;
  }
}

/// Greedy nearest-neighbor construction, O(n²).
///
/// Starts at [Problem.start], repeatedly moves to the closest unvisited node,
/// and keeps [Problem.end] (if any) for last.
List<int> nearestNeighbor(Problem p) {
  final n = p.n;
  final visited = List<bool>.filled(n, false);
  final route = <int>[p.start];
  visited[p.start] = true;
  final end = p.end;
  if (end != null) visited[end] = true;

  var current = p.start;
  final remaining = n - (end != null ? 2 : 1);
  for (var step = 0; step < remaining; step++) {
    var best = -1;
    var bestDist = double.infinity;
    for (var i = 0; i < n; i++) {
      if (visited[i]) continue;
      final dist = p.d(current, i);
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    visited[best] = true;
    route.add(best);
    current = best;
  }
  if (end != null) route.add(end);
  return route;
}

/// Improves [route] in place with 2-opt and Or-opt moves until no improving
/// move remains or [deadline] expires.
///
/// Works for closed tours, open paths and paths with a fixed end, and for
/// asymmetric distance matrices (segment reversal costs are accounted for).
void localSearch(Problem p, List<int> route,
    {Stopwatch? clock, Duration? deadline}) {
  if (p.n < 3) return;
  final ls = _LocalSearch(p, route, clock, deadline);
  var improved = true;
  while (improved && !ls.timedOut) {
    improved = false;
    while (ls.twoOptPass()) {
      improved = true;
      if (ls.timedOut) return;
    }
    if (ls.orOptPass()) improved = true;
  }
}

class _LocalSearch {
  _LocalSearch(this.p, this.r, this.clock, this.deadline)
      : n = p.n,
        // Last position whose node may be moved.
        hi = p.end != null ? p.n - 2 : p.n - 1,
        fwd = Float64List(p.n),
        bwd = Float64List(p.n) {
    _updatePrefix();
  }

  final Problem p;
  final List<int> r;
  final int n;
  final int hi;
  final Stopwatch? clock;
  final Duration? deadline;

  /// fwd[k] = cost of r[0] -> ... -> r[k]; bwd[k] = same path walked
  /// backwards. Only needed for asymmetric matrices.
  final Float64List fwd;
  final Float64List bwd;

  bool get timedOut =>
      clock != null && deadline != null && clock!.elapsed >= deadline!;

  /// Successor of position k, or -1 if there is none (open path end).
  int next(int k) => k + 1 < n ? r[k + 1] : (p.closed ? r[0] : -1);

  void _updatePrefix() {
    if (p.symmetric) return;
    fwd[0] = 0;
    bwd[0] = 0;
    for (var k = 1; k < n; k++) {
      fwd[k] = fwd[k - 1] + p.d(r[k - 1], r[k]);
      bwd[k] = bwd[k - 1] + p.d(r[k], r[k - 1]);
    }
  }

  /// Extra cost of walking r[i..j] backwards instead of forwards.
  double _reversalPenalty(int i, int j) =>
      p.symmetric ? 0.0 : (bwd[j] - bwd[i]) - (fwd[j] - fwd[i]);

  /// One sweep of 2-opt (segment reversal). Returns true if anything changed.
  bool twoOptPass() {
    var changed = false;
    for (var i = 1; i < hi; i++) {
      if (timedOut) break;
      for (var j = i + 1; j <= hi; j++) {
        final a = r[i - 1], b = r[i], c = r[j], dn = next(j);
        final delta = p.d(a, c) +
            p.e(b, dn) -
            p.d(a, b) -
            p.e(c, dn) +
            _reversalPenalty(i, j);
        if (delta < -_eps) {
          _reverse(i, j);
          _updatePrefix();
          changed = true;
        }
      }
    }
    return changed;
  }

  /// One sweep of Or-opt: move a segment of 1–3 nodes elsewhere, optionally
  /// reversed. Returns true if anything changed.
  bool orOptPass() {
    var changed = false;
    final pMax = p.end != null ? n - 2 : n - 1;
    for (var len = 1; len <= 3; len++) {
      var i = 1;
      while (i + len - 1 <= hi) {
        if (timedOut) return changed;
        final last = i + len - 1;
        final s0 = r[i], sL = r[last], prev = r[i - 1], nx = next(last);
        final removeGain = p.d(prev, s0) + p.e(sL, nx) - p.e(prev, nx);
        final revPenalty = _reversalPenalty(i, last);

        var bestDelta = -_eps;
        var bestK = -1;
        var bestReversed = false;
        for (var k = 0; k <= pMax; k++) {
          if (k >= i - 1 && k <= last) continue;
          final a = r[k], b = next(k);
          final base = -p.e(a, b) - removeGain;
          final dFwd = base + p.d(a, s0) + p.e(sL, b);
          if (dFwd < bestDelta) {
            bestDelta = dFwd;
            bestK = k;
            bestReversed = false;
          }
          if (len == 1) continue; // Reversing one node changes nothing.
          final dRev = base + p.d(a, sL) + p.e(s0, b) + revPenalty;
          if (dRev < bestDelta) {
            bestDelta = dRev;
            bestK = k;
            bestReversed = true;
          }
        }
        if (bestK >= 0) {
          _moveSegment(i, len, bestK, bestReversed);
          _updatePrefix();
          changed = true;
          // Re-examine the same position, which now holds different nodes.
        } else {
          i++;
        }
      }
    }
    return changed;
  }

  void _reverse(int i, int j) {
    while (i < j) {
      final t = r[i];
      r[i] = r[j];
      r[j] = t;
      i++;
      j--;
    }
  }

  /// Moves r[i..i+len-1] to sit right after the node currently at position k.
  void _moveSegment(int i, int len, int k, bool reversed) {
    var segment = r.sublist(i, i + len);
    if (reversed) segment = segment.reversed.toList();
    r.removeRange(i, i + len);
    final insertAt = k < i ? k + 1 : k + 1 - len;
    r.insertAll(insertAt, segment);
  }
}

/// Exact Held–Karp dynamic program, O(n² · 2ⁿ) time and O(n · 2ⁿ) memory.
///
/// Returns a provably optimal route for [p].
List<int> heldKarp(Problem p) {
  final n = p.n;
  if (n == 1) return [p.start];

  // Nodes other than start, re-indexed 0..m-1.
  final nodes = <int>[
    for (var i = 0; i < n; i++)
      if (i != p.start) i,
  ];
  final m = nodes.length;
  final full = (1 << m) - 1;
  final size = (1 << m) * m;
  final dp = Float64List(size)..fillRange(0, size, double.infinity);
  final parent = Int8List(size)..fillRange(0, size, -1);

  for (var j = 0; j < m; j++) {
    dp[(1 << j) * m + j] = p.d(p.start, nodes[j]);
  }

  for (var mask = 1; mask <= full; mask++) {
    for (var j = 0; j < m; j++) {
      if (mask & (1 << j) == 0) continue;
      final cur = dp[mask * m + j];
      if (cur == double.infinity) continue;
      final from = nodes[j];
      for (var k = 0; k < m; k++) {
        if (mask & (1 << k) != 0) continue;
        final nextMask = mask | (1 << k);
        final cand = cur + p.d(from, nodes[k]);
        final idx = nextMask * m + k;
        if (cand < dp[idx]) {
          dp[idx] = cand;
          parent[idx] = j;
        }
      }
    }
  }

  var bestJ = -1;
  if (p.end != null) {
    bestJ = nodes.indexOf(p.end!);
  } else {
    var best = double.infinity;
    for (var j = 0; j < m; j++) {
      final total =
          dp[full * m + j] + (p.closed ? p.d(nodes[j], p.start) : 0.0);
      if (total < best) {
        best = total;
        bestJ = j;
      }
    }
  }

  final reversed = <int>[];
  var mask = full;
  var j = bestJ;
  while (j >= 0) {
    reversed.add(nodes[j]);
    final pj = parent[mask * m + j];
    mask &= ~(1 << j);
    j = pj;
  }
  return [p.start, ...reversed.reversed];
}

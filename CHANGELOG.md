## 0.1.0

### Added
- `TspRouteFinder.solve` and `TspRouteFinder.solveMatrix` with a rich
  `TspResult` (`route`, `closedRoute`, `totalDistance`, `isOptimal`,
  `strategy`, `reorder`).
- `TspStrategy.exact`: Held–Karp solver that returns the optimal route for up
  to 16 stops.
- `TspStrategy.optimized`: nearest neighbor followed by 2-opt and Or-opt local
  search. Routes are about 16% shorter than 0.0.x on typical inputs.
- `TspStrategy.auto` (default): exact for up to 12 stops, optimized above.
- One-way routes (`returnToStart: false`) and a fixed last stop (`endIndex`).
- Custom distance functions and distance matrices, including asymmetric ones.
- Optional `timeLimit` for the optimized strategy.
- `TspLocation` with `distanceTo`, `haversineDistance`, and
  `TspRouteFinder.routeDistance`.
- API documentation, a runnable example, tests and a benchmark.

### Changed
- The package is now pure Dart with no dependencies. It no longer depends on
  Flutter, so it also runs on servers and CLIs and still works in any Flutter
  app.
- `TspPackage.calculateTspRoute` now uses `TspStrategy.auto` and returns much
  shorter routes.
- `tspNearestNeighbor` returns a new list on every call.

### Deprecated
- `CitiesLocations`, `TspPackage`, `tspNearestNeighbor`, `calculateDistance`
  and `radians`. They still work and will be removed in 1.0.0.

### Removed
- The public global variable `tspRoute`, which every call to
  `tspNearestNeighbor` overwrote.

## 0.0.3

- Added `CitiesLocations` and `startingLocationIndex`.
- Removed the `google_maps_flutter` dependency.

## 0.0.2

- Maintenance release.

## 0.0.1

- Initial release with the nearest-neighbor algorithm.

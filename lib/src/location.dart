import 'dart:math' as math;

/// Mean radius of the Earth in kilometers, used by [haversineDistance].
const double earthRadiusKm = 6371.0088;

/// A point on Earth identified by its [latitude] and [longitude] in degrees.
///
/// ```dart
/// const cairo = TspLocation(latitude: 30.0444, longitude: 31.2357, name: 'Cairo');
/// ```
class TspLocation {
  /// Creates a location from [latitude] and [longitude] in decimal degrees.
  ///
  /// [name] is an optional human-readable label; it is not used by the solver.
  const TspLocation({
    required this.latitude,
    required this.longitude,
    this.name,
  });

  /// Latitude in decimal degrees, in the range `[-90, 90]`.
  final double latitude;

  /// Longitude in decimal degrees, in the range `[-180, 180]`.
  final double longitude;

  /// Optional label, for example a city or customer name.
  final String? name;

  /// Great-circle distance from this location to [other], in kilometers.
  double distanceTo(TspLocation other) => haversineDistance(this, other);

  @override
  bool operator ==(Object other) =>
      other is TspLocation &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.name == name;

  @override
  int get hashCode => Object.hash(latitude, longitude, name);

  @override
  String toString() => name == null
      ? 'TspLocation($latitude, $longitude)'
      : 'TspLocation($name: $latitude, $longitude)';
}

/// Legacy location type kept for compatibility with version 0.0.3.
///
/// Prefer [TspLocation], which this class extends, so a
/// `List<CitiesLocations>` can be passed to every API that accepts
/// `List<TspLocation>`.
@Deprecated('Use TspLocation instead. Will be removed in 1.0.0.')
class CitiesLocations extends TspLocation {
  /// Creates a legacy location. [cityName] is stored as [TspLocation.name].
  CitiesLocations({
    required String cityName,
    required super.latitude,
    required super.longitude,
  }) : super(name: cityName);

  /// The city name passed to the constructor.
  String get cityName => name!;
}

/// Great-circle distance between [a] and [b] in kilometers, using the
/// haversine formula.
///
/// This is the default distance function used by the solver.
double haversineDistance(TspLocation a, TspLocation b) {
  final lat1 = _toRadians(a.latitude);
  final lat2 = _toRadians(b.latitude);
  final dLat = lat2 - lat1;
  final dLon = _toRadians(b.longitude - a.longitude);

  final sinLat = math.sin(dLat / 2);
  final sinLon = math.sin(dLon / 2);
  final h = sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLon * sinLon;
  return 2 * earthRadiusKm * math.asin(math.sqrt(math.min(1.0, h)));
}

double _toRadians(double degrees) => degrees * math.pi / 180;

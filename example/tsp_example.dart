import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tsp_route_finder/tsp_route_finder.dart';

void main() async {
  // Define a list of LatLng locations
  final List<LatLng> locations = [
    const LatLng(42.3601, -71.0589),
    const LatLng(34.0522, -118.2437),
    const LatLng(37.7749, -122.4194),
    const LatLng(39.9526, -75.1652),
  ];

  // Calculate the TSP route
  final List<int> tspRoute = await TspPackage.calculateTspRoute(locations);

  print('TSP Route: $tspRoute');
}

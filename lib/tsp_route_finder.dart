import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TspPackage {
  static Future<List<int>> calculateTspRoute(List<LatLng> locations) async {
    // Convert CitiesLatLong to LatLng
    final List<LatLng> latLngLocations = locations
        .map((city) => LatLng(city.latitude, city.longitude))
        .toList();

    // Call the TSP algorithm
    final List<int> tspRoute = tspNearestNeighbor(latLngLocations);

    return tspRoute;
  }
}

List<int> tspRoute = [];
List<int> tspNearestNeighbor(List<LatLng> locations) {
  tspRoute.clear();
  final int numLocations = locations.length;

  // Choose a random starting location
  final Random random = Random();
  int currentLocationIndex = random.nextInt(numLocations);
  tspRoute.add(currentLocationIndex);

  // Create a set to keep track of visited locations
  final Set<int> visitedLocations = {currentLocationIndex};

  while (visitedLocations.length < numLocations) {
    double minDistance = double.infinity;
    int nearestLocationIndex = -1;

    // Find the nearest unvisited location
    for (int i = 0; i < numLocations; i++) {
      if (!visitedLocations.contains(i)) {
        final double distance = calculateDistance(
            locations[currentLocationIndex], locations[i]);
        if (distance < minDistance) {
          minDistance = distance;
          nearestLocationIndex = i;
        }
      }
    }

    // Add the nearest location to the TSP route
    tspRoute.add(nearestLocationIndex);
    visitedLocations.add(nearestLocationIndex);
    currentLocationIndex = nearestLocationIndex;
  }
  return tspRoute;
}

double calculateDistance(LatLng location1, LatLng location2) {
  final double lat1 = location1.latitude;
  final double lon1 = location1.longitude;
  final double lat2 = location2.latitude;
  final double lon2 = location2.longitude;

  const double earthRadius = 6371; // Earth's radius in kilometers

  final double dLat = radians(lat2 - lat1);
  final double dLon = radians(lon2 - lon1);

  final double a = sin(dLat / 2) * sin(dLat / 2) +
      cos(radians(lat1)) * cos(radians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

  final double distance = earthRadius * c;
  return distance;
}

double radians(double degrees) {
  return degrees * pi / 180;
}
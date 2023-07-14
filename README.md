<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages).
-->

# TSP Package

TSP Package is a Dart package that provides a solution for the Traveling Salesman Problem (TSP). It includes an implementation of the Nearest Neighbor algorithm to find an approximate solution for the TSP route based on a list of locations.

## Features

- Calculate the Traveling Salesman Problem (TSP) route using the Nearest Neighbor algorithm.
- Support for calculating routes based on latitude and longitude coordinates using the `google_maps_flutter` package.

## Getting Started

To start using the TSP Package, make sure you have added it as a dependency in your Dart project's `pubspec.yaml` file. For example:

```yaml
dependencies:
  tsp_package: ^1.0.

## Usage Example

Here's an example of how to use the TSP Package to calculate the Traveling Salesman Problem (TSP) route based on a list of locations:

```dart
import 'package:tsp_package/tsp_package.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() async {
  // Define a list of LatLng locations
  final List<LatLng> locations = [
    LatLng(42.3601, -71.0589),
    LatLng(34.0522, -118.2437),
    LatLng(37.7749, -122.4194),
    LatLng(39.9526, -75.1652),
  ];

  // Calculate the TSP route
  final List<int> tspRoute = await TspPackage.calculateTspRoute(locations);

  print('TSP Route: $tspRoute');
}

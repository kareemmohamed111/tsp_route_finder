// Picks the right background runner for the platform:
// a real isolate on native platforms, the event loop on the web.
export 'background_stub.dart' if (dart.library.io) 'background_io.dart';

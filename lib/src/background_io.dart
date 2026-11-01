import 'dart:isolate';

/// Runs [computation] on a new isolate so it does not block the caller.
Future<R> runInBackground<R>(R Function() computation) =>
    Isolate.run(computation);

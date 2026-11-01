/// Web fallback: browsers have no shared-memory isolates, so [computation]
/// runs on the event loop (still asynchronous, but on the same thread).
Future<R> runInBackground<R>(R Function() computation) => Future(computation);

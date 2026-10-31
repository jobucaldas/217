import 'message_worker_stub.dart'
    if (dart.library.io) 'message_worker_io.dart' as impl;

/// Turns the periodic background inbox check (Android, about every
/// 15 minutes while online) on or off. No server push: this is what lets
/// message notifications arrive while 217 is in the background or closed.
/// Never throws.
Future<void> syncMessageWorker({required bool enabled}) =>
    impl.syncMessageWorker(enabled: enabled);

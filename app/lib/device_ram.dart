// Total physical RAM on this device, or null when it can't be read — used by
// device_fit.dart to rate on-device (GGUF) models when there's no backend to
// ask (Android never has one by design; Windows falls back to this too when
// the backend is unreachable — see model_pool.dart's refresh()).
//
// Conditional import so this stays importable from web builds, where
// dart:ffi and dart:io both fail to compile — same shape as
// platform_check.dart.
export 'device_ram_stub.dart' if (dart.library.io) 'device_ram_io.dart';

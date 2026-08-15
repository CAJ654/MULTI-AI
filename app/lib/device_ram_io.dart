// Selected wherever dart:io is available — see device_ram.dart. Two
// different mechanisms behind one signature, because there's no portable
// "how much RAM does this machine have" call:
//
//  - Windows reads it directly via GlobalMemoryStatusEx, the same Win32 API
//    Multi-AI/multi_ai/hardware.pyx's _total_ram_gb() already calls through
//    Python's ctypes for the backend machine — this is the app-side
//    equivalent for when there's no backend to ask. dart:ffi is part of the
//    Dart SDK; only the allocator (package:ffi's calloc) is a real
//    dependency, and it's already resolved transitively (see pubspec.yaml).
//  - Android has no FFI equivalent reachable from Dart, so it goes through
//    MainActivity.kt's platform channel instead — the same channel
//    download_foreground_service.dart uses for the download notification.
//
// Every other platform (Linux, macOS, iOS) returns null, same as an
// unreadable machine on the Python side: an honest "unknown" rating rather
// than a guess.
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' show calloc;
import 'package:flutter/services.dart';

const MethodChannel _deviceChannel = MethodChannel('multiai/device');

Future<double?> totalRamGb() async {
  if (Platform.isWindows) return _windowsTotalRamGb();
  if (Platform.isAndroid) return _androidTotalRamGb();
  return null;
}

Future<double?> _androidTotalRamGb() async {
  try {
    final bytes = await _deviceChannel.invokeMethod<int>('totalRamBytes');
    if (bytes == null || bytes <= 0) return null;
    return bytes / (1024 * 1024 * 1024);
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

// MEMORYSTATUSEX, field-for-field the same layout hardware.pyx's ctypes
// structure declares.
final class _MemoryStatusEx extends ffi.Struct {
  @ffi.Uint32()
  external int dwLength;
  @ffi.Uint32()
  external int dwMemoryLoad;
  @ffi.Uint64()
  external int ullTotalPhys;
  @ffi.Uint64()
  external int ullAvailPhys;
  @ffi.Uint64()
  external int ullTotalPageFile;
  @ffi.Uint64()
  external int ullAvailPageFile;
  @ffi.Uint64()
  external int ullTotalVirtual;
  @ffi.Uint64()
  external int ullAvailVirtual;
  @ffi.Uint64()
  external int ullAvailExtendedVirtual;
}

typedef _GlobalMemoryStatusExNative = ffi.Int32 Function(ffi.Pointer<_MemoryStatusEx>);
typedef _GlobalMemoryStatusExDart = int Function(ffi.Pointer<_MemoryStatusEx>);

double? _windowsTotalRamGb() {
  final status = calloc<_MemoryStatusEx>();
  try {
    status.ref.dwLength = ffi.sizeOf<_MemoryStatusEx>();
    final globalMemoryStatusEx = ffi.DynamicLibrary.open('kernel32.dll')
        .lookupFunction<_GlobalMemoryStatusExNative, _GlobalMemoryStatusExDart>(
      'GlobalMemoryStatusEx',
    );
    if (globalMemoryStatusEx(status) == 0) return null;
    return status.ref.ullTotalPhys / (1024 * 1024 * 1024);
  } catch (_) {
    return null;
  } finally {
    calloc.free(status);
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:velopack_flutter/velopack_flutter.dart';

import 'backend_process.dart';
import 'startup_gate.dart';
import 'update_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Velopack's updater re-runs the installed executable with one of these
  // during install, update and uninstall. They are lifecycle callbacks, not a
  // user launching the app, so they have to exit before anything builds a
  // window — otherwise the UI flashes on screen partway through an install.
  // windows/runner/main.cpp already forwards argv into this entrypoint, so no
  // native-side change is needed to see them.
  if (args.any((arg) => arg.startsWith('--veloapp-'))) {
    // The one hook with work to do. Velopack removes its own install root and
    // nothing else, so the dependency stack next door is ours to clean up.
    // Both steps are near-instant by design — see removeRuntimeOnUninstall,
    // which explains how it stays inside the hook's 30-second budget.
    if (args.contains('--veloapp-uninstall')) {
      BackendRuntime.removeRuntimeOnUninstall();
    }
    exit(0);
  }

  // Only records the feed URL — it makes no network call and reads nothing
  // from disk, so it is safe on a `flutter run` build that Velopack never
  // installed. The calls that do need a real install live in [UpdateService],
  // which is gated on a packaged build and swallows the failure regardless.
  //
  // Guarded anyway because this is on the launch path: it loads the Velopack
  // native library, and if that ever fails to load there is no version of
  // "cannot check for updates" that justifies refusing to start the app.
  try {
    await initializeVelopack(url: UpdateService.feedUrl);
  } catch (_) {
    // Updates are unavailable this session. Nothing else depends on it.
  }

  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Multi-AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      // Not ChatScreen directly: a packaged build has to provision and start
      // the Python backend first. In development the gate falls straight
      // through. See startup_gate.dart.
      home: const StartupGate(),
    );
  }
}

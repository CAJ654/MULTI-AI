import 'package:flutter/material.dart';

import 'startup_gate.dart';

void main() {
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

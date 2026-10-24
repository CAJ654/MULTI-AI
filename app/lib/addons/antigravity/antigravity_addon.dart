import 'package:flutter/material.dart';

import '../../platform_check.dart';
import '../addon.dart';
import 'antigravity_controller.dart';
import 'antigravity_main_pane.dart';

/// Serves the app's models over a loopback OpenAI-compatible endpoint so a
/// community proxy in front of Google Antigravity can use them. See
/// `local_model_server.dart` for what the endpoint does and doesn't offer, and
/// the pane for what's known (and not) about the Antigravity side.
///
/// Windows only: Antigravity is a desktop IDE, and the Android build has no
/// loopback peer to serve.
class AntigravityAddOn extends AddOn {
  AntigravityAddOn();

  AntigravityController? _controller;

  @override
  AddOnManifest get manifest => const AddOnManifest(
        id: 'antigravity',
        title: 'Antigravity',
        icon: Icons.hub_outlined,
        order: 6,
        requires: [HostCapability.modelPool],
      );

  @override
  Future<void> onEnable(AddOnContext context) async {
    if (!isWindowsHost) {
      return;
    }
    _controller = AntigravityController(modelPool: context.modelPool);
  }

  @override
  Future<void> onDisable() async {
    _controller?.dispose();
    _controller = null;
  }

  @override
  AddOnSurface registerUI(AddOnContext context) {
    final controller = _controller;
    if (controller == null) {
      return AddOnSurface(mainPane: (_) => _unavailablePane());
    }
    return AddOnSurface(mainPane: (_) => AntigravityMainPane(controller: controller));
  }

  Widget _unavailablePane() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hub_outlined, size: 52, color: Colors.deepPurple.shade200),
              const SizedBox(height: 16),
              const Text('Antigravity',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 10),
              const Text(
                'Only available on Windows. Antigravity is a desktop IDE, and this '
                'tab serves your models to it from this PC.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

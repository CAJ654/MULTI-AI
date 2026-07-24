import 'package:flutter/material.dart';

import 'addon.dart';

/// An add-on that owns its tab and nothing else yet — the tab exists, the
/// contract is satisfied, and there is one obvious place to put the behavior
/// when it gets written.
///
/// Orchestration and Code are both this. They declare `model_pool` even though
/// they don't call it yet: it is the capability they will need, and declaring
/// it now means the wiring is exercised rather than theoretical.
class PlaceholderAddOn extends AddOn {
  const PlaceholderAddOn({
    required this.manifest,
    required this.blurb,
  });

  @override
  final AddOnManifest manifest;

  /// One sentence on what will eventually live here.
  final String blurb;

  @override
  AddOnSurface registerUI(AddOnContext context) {
    return AddOnSurface(
      sidebarPanel: (_) => _UnderConstruction(manifest: manifest, blurb: blurb),
      mainPane: (_) => _UnderConstruction(
        manifest: manifest,
        blurb: blurb,
        iconSize: 52,
        titleSize: 20,
        maxWidth: 420,
      ),
    );
  }
}

class _UnderConstruction extends StatelessWidget {
  const _UnderConstruction({
    required this.manifest,
    required this.blurb,
    this.iconSize = 34,
    this.titleSize = 15,
    this.maxWidth = 260,
  });

  final AddOnManifest manifest;
  final String blurb;
  final double iconSize;
  final double titleSize;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(manifest.icon, size: iconSize, color: Colors.deepPurple.shade200),
              const SizedBox(height: 14),
              Text(manifest.title,
                  style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A2E14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.construction, size: 14, color: Colors.amber),
                    SizedBox(width: 6),
                    Text('Under construction',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                blurb,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.4, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

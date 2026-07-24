import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../model_detail_screen.dart';
import '../../model_fit_badge.dart';
import '../../model_pool.dart';
import '../../on_device_engine.dart';
import '../../theme.dart';
import '../addon.dart';

/// Browses the model roster: what exists, how big it is, whether this machine
/// can run it, and (through each model's detail page) downloading and deleting
/// the weights.
///
/// The management surface for the `model_pool` capability, so it declares it
/// like any other add-on rather than getting privileged access.
class ModelsAddOn extends AddOn {
  const ModelsAddOn();

  @override
  AddOnManifest get manifest => const AddOnManifest(
        id: 'models',
        title: 'Models',
        icon: Icons.dns_outlined,
        order: 0,
        requires: [HostCapability.modelPool],
      );

  @override
  AddOnSurface registerUI(AddOnContext context) {
    final pool = context.modelPool;
    return AddOnSurface(
      sidebarPanel: (_) => ModelRosterList(pool: pool),
      mainPane: (_) => ModelsPane(pool: pool),
    );
  }
}

/// The roster itself: hardware header plus one card per model. Lives in the
/// sidebar on a wide window and in the drawer on a phone.
class ModelRosterList extends StatelessWidget {
  const ModelRosterList({super.key, required this.pool});

  final ModelPool pool;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pool,
      builder: (context, _) {
        if (pool.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (pool.models.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No models available', style: TextStyle(color: Colors.white54)),
            ),
          );
        }
        final specs = pool.deviceSpecs;
        return Column(
          children: [
            if (specs != null) _DeviceSummary(specs: specs),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: pool.models.length,
                itemBuilder: (context, i) => ModelCard(model: pool.models[i], pool: pool),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The main pane while the Models tab is active.
///
/// Deliberately not a second copy of the roster: the list is already in the
/// sidebar, and rendering it twice puts every model on screen twice with two
/// scroll positions to keep in sync. A model's actual detail opens as a full
/// route when its card is tapped, so what belongs here is the pointer to it
/// plus a count of what's installed.
class ModelsPane extends StatelessWidget {
  const ModelsPane({super.key, required this.pool});

  final ModelPool pool;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pool,
      builder: (context, _) {
        final total = pool.models.length;
        final downloaded = pool.downloadedIds.length;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dns_outlined, size: 52, color: Colors.deepPurple.shade200),
                  const SizedBox(height: 16),
                  const Text('Model library',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
                  const SizedBox(height: 10),
                  Text(
                    pool.loading
                        ? 'Loading the roster…'
                        : '$downloaded of $total downloaded. Pick one from the list to '
                            'see its full spec, or to download or delete its weights.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Header naming the hardware every fit badge below was judged against —
/// without it, a card reading "Not recommended" gives no way to tell whether
/// the app misjudged the machine or the model is genuinely too big.
class _DeviceSummary extends StatelessWidget {
  const _DeviceSummary({required this.specs});

  final DeviceSpecs specs;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(Icons.memory_outlined, size: 16, color: Colors.deepPurple.shade200),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your hardware',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70)),
                const SizedBox(height: 2),
                Text(specs.summary,
                    style: const TextStyle(fontSize: 11, color: Colors.white38)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ModelCard extends StatelessWidget {
  const ModelCard({super.key, required this.model, required this.pool});

  final ModelInfo model;
  final ModelPool pool;

  @override
  Widget build(BuildContext context) {
    final m = model;
    // Everything here runs locally on this machine — there's no cloud call
    // anywhere in this app. The distinction is *how*: in-app via llama.cpp
    // (llamadart) vs. via the local Python backend process (transformers).
    final inApp = m.id == onDeviceModelId || m.gguf != null;
    final details = [
      if (m.params != null) '${m.params} params',
      if (m.sizeGb != null) '~${m.sizeGb!.toStringAsFixed(m.sizeGb! < 1 ? 2 : 1)} GB',
    ].join(' • ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ModelDetailScreen(
                model: m,
                runsInApp: inApp,
                source: inApp ? ModelPool.localSourceOf(m) : null,
                api: inApp ? null : pool.api,
              ),
            ));
            // The model's downloaded state may have changed (download/delete)
            // while its detail page was open — keep the chat picker in sync.
            pool.refreshDownloaded();
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(inApp ? Icons.smartphone_outlined : Icons.dns_outlined,
                    size: 18, color: Colors.deepPurple.shade200),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // The name yields first: in a ~184px sidebar a long
                          // name would otherwise wrap to three lines or shove
                          // the badge off the edge.
                          Flexible(
                            child: Text(m.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                          ),
                          if (m.fit != null) ...[
                            const SizedBox(width: 6),
                            ModelFitBadge(fit: m.fit!, compact: true),
                          ],
                        ],
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(details, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      ],
                      const SizedBox(height: 2),
                      Text(inApp ? 'In-app (llama.cpp)' : 'Local backend (Python)',
                          style: const TextStyle(fontSize: 11, color: Colors.white38)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Colors.white24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

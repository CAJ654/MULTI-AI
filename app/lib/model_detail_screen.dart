import 'package:flutter/material.dart';

import 'api_client.dart';
import 'theme.dart';

/// Full-page breakdown of a single model, pushed when its card is tapped in
/// the sidebar's Models tab (see `chat_screen.dart`'s `_buildModelCard`).
class ModelDetailScreen extends StatelessWidget {
  const ModelDetailScreen({super.key, required this.model, required this.runsInApp});

  final ModelInfo model;

  /// Whether this model runs in-app via llama.cpp, vs. via the local Python
  /// backend. Both run entirely on this machine — see chat_screen.dart.
  final bool runsInApp;

  static const _unknown = 'Not documented for this model yet';

  String _formatContext(int? tokens) {
    if (tokens == null) return _unknown;
    if (tokens % 1024 == 0) return '${tokens ~/ 1024}K tokens';
    return '$tokens tokens';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: mainColor,
      appBar: AppBar(
        backgroundColor: mainColor,
        elevation: 0,
        title: Text(model.name),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatsRow(),
                const SizedBox(height: 24),
                _buildSection(Icons.category_outlined, 'Modality', model.modality ?? _unknown),
                _buildSection(
                  Icons.auto_awesome_outlined,
                  'Core Strengths & Intelligence Profile',
                  model.strengths ?? _unknown,
                ),
                _buildSection(
                  Icons.speed_outlined,
                  'Intelligence-to-Speed Ratio',
                  model.speedProfile ?? _unknown,
                ),
                _buildSection(
                  Icons.memory_outlined,
                  'Context Window',
                  _formatContext(model.contextTokens),
                ),
                _buildSection(Icons.gavel_outlined, 'Open Source License', model.license ?? _unknown),
                _buildSection(
                  runsInApp ? Icons.smartphone_outlined : Icons.dns_outlined,
                  'Runs',
                  runsInApp ? 'In-app (llama.cpp) — no server needed' : 'Local backend (Python, transformers)',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _buildStatTile('Parameters', model.params ?? '—')),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatTile(
            'Download size',
            model.sizeGb != null ? '~${model.sizeGb!.toStringAsFixed(model.sizeGb! < 1 ? 2 : 1)} GB' : '—',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _buildStatTile('Context', _formatContext(model.contextTokens))),
      ],
    );
  }

  Widget _buildStatTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildSection(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.deepPurple.shade200),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.5)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../theme.dart';

/// One-time explainer shown the first time the web-search toggle is turned
/// on in a Chat conversation — the "what leaves your device" half of this
/// feature's consent model (the other half is installing the component at
/// all, from the Add-ons tab). Same dialog shape as `storage_settings_dialog.dart`
/// / `thinking_settings_dialog.dart` / `tool_approval_dialog.dart`, so it
/// reads as this app's own dialog rather than a one-off.
///
/// The copy here is the one place this feature's honesty about "local ≠
/// private from upstream" is enforced in the UI — see the web-access plan's
/// ethics table. It must not be softened to sound more private than it is.
class WebAccessExplainerDialog extends StatelessWidget {
  const WebAccessExplainerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.public, size: 20, color: Colors.deepPurple.shade200),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Turn on web search?',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'When this is on, a message you send may be used as a search query '
              'against a SearXNG instance running locally on this machine — no '
              'account, no API key.',
              style: TextStyle(fontSize: 13, height: 1.5, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            const Text(
              "That's not the same as staying fully offline, though: SearXNG "
              'still has to relay the search to engines like Bing and '
              'DuckDuckGo over the open internet, from your own connection — '
              'those engines (and any page or video fetched) see the query or '
              'URL and your IP address, the same as if you visited them '
              'yourself.',
              style: TextStyle(fontSize: 13, height: 1.5, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            const Text(
              "Nothing is sent anywhere until you turn this on, and it's "
              'per-message — you can turn it off again any time. Sources used '
              'in a reply are always shown so you can check them yourself.',
              style: TextStyle(fontSize: 13, height: 1.5, color: Colors.white54),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Not now'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple.shade400),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Enable web search'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

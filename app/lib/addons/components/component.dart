/// A downloadable local service the Add-ons tab manages — see
/// `components_addon.dart`. Deliberately not named anything close to `AddOn`:
/// every tab in this app already is one (see `addon.dart`), and this is a
/// different concept one level down — a piece of software an add-on's
/// *feature* depends on, not a tab of its own.
enum ComponentKind {
  /// A long-running local process this app supervises on its own port —
  /// started, health-checked, stopped. SearXNG.
  server,

  /// No persistent process at all: every use is a fresh one-shot subprocess
  /// that exits on its own. yt-dlp.
  tool,
}

/// What the Add-ons tab shows and installs/deletes for one component.
class LocalComponent {
  const LocalComponent({
    required this.id,
    required this.name,
    required this.kind,
    required this.description,
    required this.approxInstalledMb,
    this.port,
  });

  /// Stable identifier — the subdirectory name under this component's runtime
  /// root (see `ComponentRuntime.baseDir`) and the requirements asset's file
  /// name prefix (`assets/components/<id>_requirements.txt`).
  final String id;

  final String name;
  final ComponentKind kind;

  /// Shown on the detail screen: what installing this actually gets the user.
  final String description;

  /// Rough installed size in MB, shown before download so the user isn't
  /// guessing — not measured live, since that would mean walking the
  /// directory tree just to render a number that barely moves.
  final int approxInstalledMb;

  /// Fixed local port, `server`-kind components only. Null for `tool`-kind,
  /// which has no process to bind one.
  final int? port;
}

/// Every component the Add-ons tab can install. A `server`-kind component's
/// [LocalComponent.port] must be unique against every other local service
/// this app runs — see the port list in `searxng_supervisor.dart`'s doc
/// comment (main backend 8000, Colibri 8010, SearXNG 8891).
const componentCatalog = <LocalComponent>[
  LocalComponent(
    id: 'searxng',
    name: 'Web Search (SearXNG)',
    kind: ComponentKind.server,
    description:
        'Lets Chat search the web to help answer questions. Runs a small local '
        'SearXNG instance on this machine — no account, no API key, no public '
        'search-engine account tied to your queries. It still has to relay '
        'searches to engines like Bing and DuckDuckGo over the open internet, '
        'though, so this is not the same as staying fully offline; see the '
        'explainer the first time you turn it on in Chat.',
    approxInstalledMb: 90,
    port: 8891,
  ),
  LocalComponent(
    id: 'yt_dlp',
    name: 'YouTube Transcripts (yt-dlp)',
    kind: ComponentKind.tool,
    description:
        'Lets Chat read a YouTube video\'s transcript and details when you '
        'paste its link, so it can answer questions about the video without '
        'watching it for you. No account, no API key — each use runs yt-dlp '
        'as a short-lived command, not a background process.',
    approxInstalledMb: 15,
  ),
];

LocalComponent? componentById(String id) {
  for (final c in componentCatalog) {
    if (c.id == id) return c;
  }
  return null;
}

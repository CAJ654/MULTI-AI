import 'dart:convert';
import 'dart:io';

import '../components/component.dart';
import '../components/component_manager.dart';
import '../components/component_runtime.dart';
import 'web_source.dart';

/// Fetches a YouTube video's transcript and basic metadata via the yt-dlp
/// component — a one-shot subprocess call (see
/// `ComponentRuntime.runModule`), never a persistent process, unlike
/// SearXNG. Triggered from `web_grounding.dart` when a message contains a
/// video link, instead of a web search.
class YoutubeTranscriptFetcher {
  YoutubeTranscriptFetcher(this._components);

  final ComponentManager _components;

  static final _urlPattern = RegExp(
    r'(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)([\w-]{6,})',
    caseSensitive: false,
  );

  /// The first YouTube video URL found in [text], or null.
  static Uri? findVideoUrl(String text) {
    final m = _urlPattern.firstMatch(text);
    if (m == null) return null;
    final raw = m.group(0)!;
    return Uri.tryParse(raw.startsWith('http') ? raw : 'https://$raw');
  }

  static const _maxChars = 6000;

  /// The video's transcript text plus a [WebSource] describing it, or null if
  /// yt-dlp isn't installed, the video has no captions, or anything fails —
  /// callers fall back to answering without it, the same contract as
  /// [SearxngSearchClient.search] (see `web_search_client.dart`).
  Future<({String transcript, WebSource source})?> fetch(Uri videoUrl) async {
    if (!_components.isInstalled('yt_dlp')) return null;
    final runtime = ComponentRuntime(componentById('yt_dlp')!);
    final tempDir = await Directory.systemTemp.createTemp('multi_ai_yt_');
    try {
      final outBase = '${tempDir.path}${Platform.pathSeparator}transcript';
      final result = await runtime.runModule(
        'yt_dlp',
        [
          '--skip-download',
          '--write-auto-sub',
          '--write-sub',
          '--sub-lang', 'en',
          '--sub-format', 'vtt',
          '--dump-json',
          '--no-warnings',
          '-o', '$outBase.%(ext)s',
          videoUrl.toString(),
        ],
        timeout: const Duration(seconds: 25),
      );
      if (result.exitCode != 0) return null;

      final meta = _parseJsonLine(result.stdout as String);
      final title = meta?['title'] as String? ?? videoUrl.toString();
      final uploader = meta?['uploader'] as String?;

      final subtitleFile = await _findSubtitleFile(tempDir);
      if (subtitleFile == null) return null;
      final transcript = _vttToText(await subtitleFile.readAsString());
      if (transcript.isEmpty) return null;
      final truncated = transcript.length > _maxChars
          ? '${transcript.substring(0, _maxChars)}…'
          : transcript;

      return (
        transcript: truncated,
        source: WebSource(
          title: uploader != null ? '$title — $uploader' : title,
          url: videoUrl.toString(),
        ),
      );
    } catch (_) {
      return null;
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup of a temp directory the OS will reclaim anyway.
      }
    }
  }

  /// `--dump-json` prints exactly one JSON object, on its own line among any
  /// other yt-dlp chatter that survived `--no-warnings`.
  Map<String, dynamic>? _parseJsonLine(String stdout) {
    for (final line in stdout.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('{')) continue;
      try {
        return jsonDecode(trimmed) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Scans for whatever yt-dlp actually named the subtitle file rather than
  /// assuming an exact name — it appends the language code before the
  /// extension in a way this doesn't need to hardcode.
  Future<File?> _findSubtitleFile(Directory dir) async {
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.vtt')) return entity;
    }
    return null;
  }

  /// Strips WebVTT's cue timing/index/tag noise down to plain spoken text,
  /// and drops immediate repeats — auto-captions commonly re-print the
  /// previous line as a new cue scrolls in.
  String _vttToText(String vtt) {
    final out = <String>[];
    String? last;
    for (final raw in vtt.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('WEBVTT')) continue;
      if (line.contains('-->')) continue;
      if (RegExp(r'^\d+$').hasMatch(line)) continue; // cue index
      final clean = line.replaceAll(RegExp(r'<[^>]+>'), '');
      if (clean.isEmpty || clean == last) continue;
      out.add(clean);
      last = clean;
    }
    return out.join(' ');
  }
}

// Generates app/assets/on_device_roster.json from Multi-AI/multi_ai/models/*.pyx
// so Android — which never talks to the Python backend — has a real model
// roster instead of falling back to a single hardcoded on-device model.
//
// Run from the app/ directory before any Android build/run:
//
//   dart run tool/generate_on_device_roster.dart
//
// Not a Flutter script — this is a plain `dart run` build-time tool, same
// convention as tool/verify_on_device.dart. Re-run it whenever
// Multi-AI/multi_ai/models/*.pyx changes; nothing regenerates it automatically.
//
// Deliberately does NOT import verify_on_device.dart's private _parseRoster:
// that function only extracts 4 of the 9 fields ModelInfo needs and is scoped
// to a script with unrelated (llamadart/OnDeviceEngine) dependencies. This
// file duplicates the small regex core instead.

import 'dart:convert';
import 'dart:io';

/// How many `.pyx` files declare a module-level `_GGUF_SOURCE` right now.
/// Asserting this turns a regex that silently stops matching into a loud
/// build failure instead of a quietly truncated Android roster. Bump it
/// deliberately when the on-device roster grows.
const int _expectedRosterSize = 27;

void main(List<String> argv) {
  final repoRoot = _findRepoRoot();
  if (repoRoot == null) {
    stderr.writeln('Could not locate the repo root (no Multi-AI/multi_ai/models directory).');
    stderr.writeln('Run this from the app/ directory: dart run tool/generate_on_device_roster.dart');
    exit(2);
  }

  final modelsDir = Directory('$repoRoot/Multi-AI/multi_ai/models');
  final files = modelsDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.pyx'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  // Anchored at line start: a module-level assignment, not a substring match.
  // Several *_colibri.pyx files mention "_GGUF_SOURCE" only in docstring
  // prose (comparing themselves to the GGUF path) without ever assigning it —
  // a naive `contains` check would wrongly include them.
  final sourceRe = RegExp(r'^_GGUF_SOURCE\s*=\s*\(?\s*"([^"]+)"', multiLine: true);
  final mmprojRe = RegExp(r'^_GGUF_MMPROJ_SOURCE\s*=\s*\(?\s*"([^"]+)"', multiLine: true);
  final modalitiesRe = RegExp(r'^_INPUT_MODALITIES\s*=\s*\(([^)]*)\)', multiLine: true);
  final tokenRe = RegExp(r'"(\w+)"');

  final entries = <Map<String, Object?>>[];
  final missingFields = <String>[];

  for (final file in files) {
    final text = file.readAsStringSync();
    final source = sourceRe.firstMatch(text)?.group(1);
    if (source == null) continue; // server-only or external-endpoint model

    final id = file.uri.pathSegments.last.replaceAll('.pyx', '');
    final mmproj = mmprojRe.firstMatch(text)?.group(1);
    final declaredModalities = modalitiesRe.firstMatch(text)?.group(1);
    final modalities = {
      'text',
      if (declaredModalities != null)
        for (final m in tokenRe.allMatches(declaredModalities)) m.group(1)!,
    };

    final name = _extractStringField(text, 'name');
    final params = _extractStringField(text, 'params');
    final sizeGb = _extractNumberField(text, 'size_gb');
    final modality = _extractStringField(text, 'modality');
    final contextTokens = _extractNumberField(text, 'context_tokens');
    final license = _extractStringField(text, 'license');
    final strengths = _extractStringField(text, 'strengths');
    final speedProfile = _extractStringField(text, 'speed_profile');

    final entry = <String, Object?>{
      'id': id,
      'name': name,
      'available': true,
      'gguf': source,
      if (mmproj != null) 'mmproj': mmproj,
      'has_server_weights': false,
      'input_modalities': modalities.toList(),
      'params': params,
      if (sizeGb != null) 'size_gb': sizeGb,
      'modality': modality,
      if (contextTokens != null) 'context_tokens': contextTokens.toInt(),
      'license': license,
      'strengths': strengths,
      'speed_profile': speedProfile,
    };
    entries.add(entry);

    final missing = <String>[
      if (name == null) 'name',
      if (params == null) 'params',
      if (sizeGb == null) 'size_gb',
      if (modality == null) 'modality',
      if (contextTokens == null) 'context_tokens',
      if (license == null) 'license',
      if (strengths == null) 'strengths',
      if (speedProfile == null) 'speed_profile',
    ];
    if (missing.isNotEmpty) missingFields.add('$id (missing: ${missing.join(", ")})');
  }

  if (entries.length != _expectedRosterSize) {
    stderr.writeln(
        'Roster parse found ${entries.length} models, expected $_expectedRosterSize.');
    stderr.writeln('Either the regex stopped matching a file, or the roster genuinely '
        'changed size — if the latter, update _expectedRosterSize deliberately.');
    exit(3);
  }
  if (missingFields.isNotEmpty) {
    stderr.writeln('Roster entries missing required fields:');
    for (final m in missingFields) {
      stderr.writeln('  $m');
    }
    exit(3);
  }

  final assetsDir = Directory('${Directory.current.path}/assets');
  assetsDir.createSync(recursive: true);
  final outFile = File('${assetsDir.path}/on_device_roster.json');
  const encoder = JsonEncoder.withIndent('  ');
  outFile.writeAsStringSync(encoder.convert({'models': entries}));

  stdout.writeln('Wrote ${entries.length} models to ${outFile.path}');
}

/// Extracts a `"key": <string literal>` value from a Python dict literal,
/// handling both quote styles this codebase actually uses (most files use
/// double quotes; a handful use single quotes for `strengths`) and Python's
/// implicit adjacent-string-literal concatenation across lines (also used
/// for long `strengths`/`speed_profile` text). A plain single-capture regex
/// handles neither case reliably, so this scans manually instead.
String? _extractStringField(String text, String key) {
  final marker = RegExp('"${RegExp.escape(key)}"\\s*:\\s*');
  final m = marker.firstMatch(text);
  if (m == null) return null;

  var i = m.end;
  final buffer = StringBuffer();
  while (i < text.length) {
    final quote = text[i];
    if (quote != '"' && quote != "'") break;
    i++;
    final start = i;
    while (i < text.length && text[i] != quote) {
      if (text[i] == r'\') i++; // skip escaped char
      i++;
    }
    buffer.write(text.substring(start, i));
    i++; // closing quote

    // Look past whitespace: another quote with no comma in between means
    // Python's implicit string concatenation continues; anything else
    // (starting with a comma) means this field's value is complete.
    var j = i;
    while (j < text.length && (text[j] == ' ' || text[j] == '\n' || text[j] == '\r' || text[j] == '\t')) {
      j++;
    }
    if (j < text.length && (text[j] == '"' || text[j] == "'")) {
      i = j;
      continue;
    }
    break;
  }
  return buffer.isEmpty ? null : buffer.toString();
}

num? _extractNumberField(String text, String key) {
  final m = RegExp('"${RegExp.escape(key)}"\\s*:\\s*([\\d.]+)').firstMatch(text);
  if (m == null) return null;
  return num.tryParse(m.group(1)!);
}

String? _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    if (Directory('${dir.path}/Multi-AI/multi_ai/models').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

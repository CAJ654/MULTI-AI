import 'package:flutter/foundation.dart';

/// A fenced code block pulled out of a model reply, so it can be opened in the
/// workbench panel beside the chat. Modeled on Claude Artifacts and Gemini Canvas,
/// but kept to the part that needs no sandboxed WebView: showing the source.
@immutable
class Artifact {
  const Artifact({required this.index, required this.language, required this.code});

  /// Position among the code blocks of its reply, starting at 1.
  final int index;

  /// The info string after the opening fence (e.g. `html`, `dart`). Empty if
  /// the block had none.
  final String language;

  /// The block's contents, without the fences.
  final String code;

  /// Short label for the chip and panel header.
  String get label {
    final kind = language.isEmpty ? 'Code' : language;
    return '$kind $index';
  }

  @override
  bool operator ==(Object other) =>
      other is Artifact &&
      other.index == index &&
      other.language == language &&
      other.code == code;

  @override
  int get hashCode => Object.hash(index, language, code);
}

/// Every non-empty fenced code block in [markdown], in order. Uses the same
/// fence rules as `markdown_text.dart`: a block opens with three or more
/// backticks or tildes and closes with the same run, and an unclosed block
/// runs to the end of the text.
List<Artifact> extractArtifacts(String markdown) {
  final lines = markdown.split('\n');
  final artifacts = <Artifact>[];
  var i = 0;
  while (i < lines.length) {
    final trimmed = lines[i].trim();
    final match = RegExp(r'^(`{3,}|~{3,})(.*)$').firstMatch(trimmed);
    if (match == null) {
      i++;
      continue;
    }
    final fence = match.group(1)!;
    final language = match.group(2)!.trim().split(RegExp(r'\s+')).first;
    final body = <String>[];
    i++;
    while (i < lines.length && lines[i].trim() != fence) {
      body.add(lines[i]);
      i++;
    }
    if (i < lines.length) i++; // consume the closing fence
    final code = body.join('\n');
    if (code.trim().isNotEmpty) {
      artifacts.add(Artifact(
        index: artifacts.length + 1,
        language: language,
        code: code,
      ));
    }
  }
  return artifacts;
}

/// Which artifact the workbench panel is showing, if any. Owned by the chat pane
/// so that opening one from any reply updates the panel beside the chat.
class WorkbenchController extends ChangeNotifier {
  Artifact? _artifact;

  Artifact? get artifact => _artifact;

  void open(Artifact artifact) {
    if (_artifact == artifact) return;
    _artifact = artifact;
    notifyListeners();
  }

  void close() {
    if (_artifact == null) return;
    _artifact = null;
    notifyListeners();
  }
}

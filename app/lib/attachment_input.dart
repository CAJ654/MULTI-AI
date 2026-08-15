import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';

import 'api_client.dart';

/// Picks images and records audio for the chat input.
///
/// Wrapped in an interface so widget tests can drive the input area without a
/// real file dialog or microphone — both of which block on platform UI that
/// never resolves under `flutter test`.
abstract class AttachmentSource {
  /// Returns the images the user chose, or an empty list if they cancelled.
  Future<List<Attachment>> pickImages();

  /// Whether a mic is present and the user has granted access to it.
  Future<bool> hasMicPermission();

  Future<void> startRecording();

  /// Stops the in-progress recording and returns it. Null if the recorder
  /// produced nothing (cancelled, or stopped before any audio was captured).
  Future<Attachment?> stopRecording();

  /// Throws away an in-progress recording without producing an attachment.
  Future<void> cancelRecording();

  Future<void> dispose();
}

/// Extensions accepted by the image picker, and the MIME type each maps to.
/// Deliberately narrow: these are the formats PIL decodes without extra
/// dependencies on the backend, so anything that gets picked here will load
/// there.
const _imageMimeTypes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'bmp': 'image/bmp',
  'webp': 'image/webp',
};

class DefaultAttachmentSource implements AttachmentSource {
  final _recorder = AudioRecorder();
  String? _recordingPath;

  @override
  Future<List<Attachment>> pickImages() async {
    // pickFiles() is multi-select by default as of file_picker 12 (no more
    // allowMultiple) and returns [] rather than null on cancel.
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _imageMimeTypes.keys.toList(),
    );
    final attachments = <Attachment>[];
    for (final file in files) {
      // readAsBytes() replaces the deprecated withData: true — it reads from
      // whichever source the platform actually populated (bytes, a local
      // path, or a stream), so we need to base64 them onto the wire anyway.
      final bytes = await file.readAsBytes();
      // PlatformFile dropped its own `extension` getter in the federated
      // rewrite (file_picker 12) — derive it from the name, same source the
      // old getter used internally.
      final dot = file.name.lastIndexOf('.');
      final extension = dot >= 0 ? file.name.substring(dot + 1) : null;
      attachments.add(Attachment(
        kind: AttachmentKind.image,
        bytes: bytes,
        mimeType: _imageMimeTypes[extension?.toLowerCase()] ?? 'image/png',
        name: file.name,
      ));
    }
    return attachments;
  }

  @override
  Future<bool> hasMicPermission() => _recorder.hasPermission();

  @override
  Future<void> startRecording() async {
    final dir = await Directory.systemTemp.createTemp('multi_ai_rec');
    final path = '${dir.path}${Platform.pathSeparator}recording.wav';
    // Uncompressed 16kHz mono: what every speech encoder resamples to anyway,
    // and it avoids depending on a platform-specific AAC/Opus encoder being
    // present. The backend's librosa decode reads it directly.
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: path,
    );
    _recordingPath = path;
  }

  @override
  Future<Attachment?> stopRecording() async {
    final path = await _recorder.stop() ?? _recordingPath;
    _recordingPath = null;
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    // Delete eagerly rather than leaving it to temp-dir cleanup — the bytes
    // are in memory now, and recordings pile up fast.
    try {
      await file.delete();
    } on FileSystemException {
      // Best-effort; a locked file just gets cleaned up with the temp dir.
    }
    if (bytes.isEmpty) return null;
    return Attachment(
      kind: AttachmentKind.audio,
      bytes: bytes,
      mimeType: 'audio/wav',
      name: 'recording.wav',
    );
  }

  @override
  Future<void> cancelRecording() async {
    await _recorder.cancel();
    final path = _recordingPath;
    _recordingPath = null;
    if (path == null) return;
    try {
      await File(path).delete();
    } on FileSystemException {
      // Nothing to clean up if it never made it to disk.
    }
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

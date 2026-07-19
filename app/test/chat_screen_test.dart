import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';

import 'package:multi_ai/api_client.dart';
import 'package:multi_ai/attachment_input.dart';
import 'package:multi_ai/chat_screen.dart';
import 'package:multi_ai/on_device_engine.dart';

/// Returns canned models instead of calling the real backend.
class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.models, {Set<String>? notCachedIds}) : _notCachedIds = notCachedIds ?? const {};

  final List<ModelInfo> models;
  final Set<String> _notCachedIds;

  @override
  Future<List<ModelInfo>> fetchModels() async => models;

  /// Attachments from the last sendChat call, for asserting what actually
  /// went out with a message.
  List<Attachment> lastAttachments = const [];

  // Never resolves, so a send leaves the UI in the "thinking" state for the
  // test to inspect.
  @override
  Future<String> sendChat({
    required String model,
    required String message,
    List<Attachment> attachments = const [],
  }) {
    lastAttachments = attachments;
    return Completer<String>().future;
  }

  // The chat screen queries cache status for every server-backed model to
  // decide whether to offer it in the picker; stub it out so tests never
  // make a real network call. Every model defaults to "already downloaded"
  // so existing assertions about what shows in the picker keep holding —
  // pass notCachedIds to test the hidden-until-downloaded behavior.
  @override
  Future<ServerModelCacheStatus> getServerModelCacheStatus(String modelId) async =>
      ServerModelCacheStatus(cached: !_notCachedIds.contains(modelId));
}

/// Stands in for llamadart's real file-backed cache manager so tests never
/// touch the actual on-device model cache directory. Every source defaults
/// to "already downloaded"; pass isCached to test the opposite.
class _FakeDownloadManager extends ThrowingModelDownloadManager {
  const _FakeDownloadManager({this.isCached = _alwaysCached});

  final bool Function(String cacheKey) isCached;

  static bool _alwaysCached(String cacheKey) => true;

  @override
  Future<ModelCacheEntry?> get(String cacheKey, {String? cacheDirectory}) async {
    if (!isCached(cacheKey)) return null;
    final now = DateTime.now().toUtc();
    return ModelCacheEntry(
      sourceCanonicalKey: cacheKey,
      cacheKey: cacheKey,
      fileName: 'fake.gguf',
      filePath: 'C:/fake-cache/fake.gguf',
      createdAt: now,
      updatedAt: now,
      bytes: 1,
    );
  }
}

/// Stands in for the real file dialog and microphone, neither of which
/// resolves under `flutter test`. Records what was asked of it and hands back
/// canned attachments.
class _FakeAttachmentSource implements AttachmentSource {
  _FakeAttachmentSource({this.micAllowed = true});

  final bool micAllowed;
  bool recording = false;
  int pickCount = 0;

  static const _pickedImage = Attachment(
    kind: AttachmentKind.image,
    // A 1x1 PNG would still need decoding to render; the chip's errorBuilder
    // covers undecodable bytes, so any placeholder works here.
    bytes: [1, 2, 3],
    mimeType: 'image/png',
    name: 'picked.png',
  );

  static const _recorded = Attachment(
    kind: AttachmentKind.audio,
    bytes: [4, 5, 6],
    mimeType: 'audio/wav',
    name: 'recording.wav',
  );

  @override
  Future<List<Attachment>> pickImages() async {
    pickCount++;
    return [_pickedImage];
  }

  @override
  Future<bool> hasMicPermission() async => micAllowed;

  @override
  Future<void> startRecording() async => recording = true;

  @override
  Future<Attachment?> stopRecording() async {
    recording = false;
    return _recorded;
  }

  @override
  Future<void> cancelRecording() async => recording = false;

  @override
  Future<void> dispose() async {}
}

/// Default test surface (800x600) is too short for the chat screen's
/// suggestion cards and overflows; match a realistic desktop window.
void _useDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('dropdown shows the on-device model plus every server model', (tester) async {
    _useDesktopSurface(tester);

    final fake = _FakeApiClient(const [
      ModelInfo(id: 'gpt2', name: 'GPT-2'),
      ModelInfo(id: 'gptOSS', name: 'GPT-OSS 20B', gguf: 'hf://ggml-org/gpt-oss-20b-GGUF/gpt-oss-20b-MXFP4.gguf'),
    ]);

    await tester.pumpWidget(MaterialApp(home: ChatScreen(apiClient: fake, downloadManager: const _FakeDownloadManager())));
    await tester.pumpAndSettle();

    // Open the dropdown so its (offstage-when-closed) menu items are findable.
    await tester.tap(find.byType(DropdownButton<ModelInfo>));
    await tester.pumpAndSettle();

    // Chat picker labels every entry with where it runs.
    expect(find.text('$onDeviceModelName (on-device)'), findsWidgets);
    expect(find.text('GPT-2 (local server)'), findsWidgets);
    expect(find.text('GPT-OSS 20B (on-device)'), findsWidgets);
  });

  testWidgets('falls back to the on-device model only when the backend is unreachable', (tester) async {
    _useDesktopSurface(tester);

    final fake = _FakeApiClient(const []);
    // fetchModels() succeeding with an empty list still exercises the merge
    // path; a real unreachable backend throws instead, which _loadModels
    // catches the same way — either way only the on-device entry should show.

    await tester.pumpWidget(MaterialApp(home: ChatScreen(apiClient: fake, downloadManager: const _FakeDownloadManager())));
    await tester.pumpAndSettle();

    expect(find.text('$onDeviceModelName (on-device)'), findsOneWidget);
  });

  testWidgets('Models tab lists params/size and Chat tab keeps the New Chat button', (tester) async {
    _useDesktopSurface(tester);

    final fake = _FakeApiClient(const [
      ModelInfo(id: 'gpt2', name: 'GPT-2', params: '124M', sizeGb: 0.55),
    ]);

    await tester.pumpWidget(MaterialApp(home: ChatScreen(apiClient: fake, downloadManager: const _FakeDownloadManager())));
    await tester.pumpAndSettle();

    // Chat tab is the default: New Chat button visible, no model metadata yet.
    expect(find.widgetWithText(FilledButton, 'New Chat'), findsOneWidget);
    expect(find.textContaining('params'), findsNothing);

    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'New Chat'), findsNothing);
    // The top-bar dropdown also shows the (unrelated) selected model's name
    // in its closed state, so this may match more than just the tab's card.
    expect(find.text(onDeviceModelName), findsWidgets);
    expect(find.textContaining('$onDeviceModelParams params'), findsOneWidget);
    expect(find.text('GPT-2'), findsOneWidget);
    expect(find.textContaining('124M params'), findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'New Chat'), findsOneWidget);
  });

  testWidgets('tapping a model card opens its detail page with the full spec', (tester) async {
    _useDesktopSurface(tester);

    final fake = _FakeApiClient(const [
      ModelInfo(
        id: 'gpt2',
        name: 'GPT-2',
        params: '124M',
        sizeGb: 0.55,
        modality: 'Text',
        contextTokens: 1024,
        license: 'MIT',
        strengths: 'A raw base model, mostly useful as a speed baseline.',
        speedProfile: 'Very fast, minimal intelligence',
      ),
    ]);

    await tester.pumpWidget(MaterialApp(home: ChatScreen(apiClient: fake, downloadManager: const _FakeDownloadManager())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GPT-2'));
    await tester.pumpAndSettle();

    expect(find.text('Modality'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Core Strengths & Intelligence Profile'), findsOneWidget);
    expect(find.text('A raw base model, mostly useful as a speed baseline.'), findsOneWidget);
    expect(find.text('Intelligence-to-Speed Ratio'), findsOneWidget);
    expect(find.text('Very fast, minimal intelligence'), findsOneWidget);
    expect(find.text('Context Window'), findsOneWidget);
    expect(find.textContaining('1K tokens'), findsWidgets);
    expect(find.text('Open Source License'), findsOneWidget);
    expect(find.text('MIT'), findsOneWidget);
    expect(find.text('124M'), findsOneWidget);
  });

  testWidgets('sending a message shows the thinking row without crashing', (tester) async {
    _useDesktopSurface(tester);

    final fake = _FakeApiClient(const [ModelInfo(id: 'gpt2', name: 'GPT-2')]);

    await tester.pumpWidget(MaterialApp(home: ChatScreen(apiClient: fake, downloadManager: const _FakeDownloadManager())));
    await tester.pumpAndSettle();

    // The dropdown defaults to the on-device model; switch to the (never
    // resolving) server model so the send goes through _api.sendChat.
    await tester.tap(find.byType(DropdownButton<ModelInfo>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPT-2 (local server)').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // The thinking row's rotating indicator starts a periodic timer, so
    // settle with an explicit pump instead of pumpAndSettle (which would
    // wait forever for a timer that never stops on its own).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('hides an undownloaded model from chat but keeps it in the Models tab', (tester) async {
    _useDesktopSurface(tester);

    const missingGguf = 'hf://ggml-org/gpt-oss-20b-GGUF/gpt-oss-20b-MXFP4.gguf';
    final fake = _FakeApiClient(const [
      ModelInfo(id: 'gpt2', name: 'GPT-2'),
      ModelInfo(id: 'gptOSS', name: 'GPT-OSS 20B', gguf: missingGguf),
    ]);
    final missingCacheKey = ModelSource.parse(missingGguf).cacheKey;
    final downloads = _FakeDownloadManager(isCached: (key) => key != missingCacheKey);

    await tester.pumpWidget(MaterialApp(home: ChatScreen(apiClient: fake, downloadManager: downloads)));
    await tester.pumpAndSettle();

    // Chat picker: downloaded models only.
    await tester.tap(find.byType(DropdownButton<ModelInfo>));
    await tester.pumpAndSettle();
    expect(find.text('$onDeviceModelName (on-device)'), findsWidgets);
    expect(find.text('GPT-2 (local server)'), findsWidgets);
    expect(find.text('GPT-OSS 20B (on-device)'), findsNothing);

    // Dismiss the still-open dropdown menu overlay before switching tabs.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Models tab: every model, downloaded or not.
    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();
    expect(find.text('GPT-OSS 20B'), findsOneWidget);
  });

  testWidgets('Models tab shows what the app can actually send, not what the '
      'checkpoint could', (tester) async {
    _useDesktopSurface(tester);

    // The data shape of gemma3n_on_device: a sibling of a natively multimodal
    // checkpoint, whose prose modality inherits "Text + Image + Audio" while
    // the backend reports text-only (llama.cpp runs just the text path). The
    // detail page must follow the latter — advertising image input that the
    // chat input then refuses to offer is what made this confusing before.
    //
    // Modelled without a `gguf` field on purpose: the detail screen builds its
    // own real download manager for in-app models, which has no fake to inject
    // and hangs under test. The derivation being asserted is independent of it.
    final fake = _FakeApiClient(const [
      ModelInfo(
        id: 'gemma3n_on_device',
        name: 'Gemma 3n E2B (On-Device)',
        modality: 'Text + Image + Audio',
        inputModalities: ['text'],
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(apiClient: fake, downloadManager: const _FakeDownloadManager()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gemma 3n E2B (On-Device)'));
    await tester.pumpAndSettle();

    expect(find.text('Modality'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Text + Image + Audio'), findsNothing);
  });

  testWidgets('an on-device vision model stays hidden until its projector is '
      'downloaded too', (tester) async {
    _useDesktopSurface(tester);

    const weights = 'hf://unsloth/gemma-3-4b-it-GGUF/gemma-3-4b-it-Q4_K_M.gguf';
    const mmproj = 'hf://unsloth/gemma-3-4b-it-GGUF/mmproj-F16.gguf';
    final fake = _FakeApiClient(const [
      ModelInfo(
        id: 'gemma_3_4b_on_device',
        name: 'Gemma 3 4B (On-Device)',
        gguf: weights,
        mmproj: mmproj,
        inputModalities: ['text', 'image'],
      ),
    ]);
    // Weights present, projector missing — the half-downloaded state. Offering
    // this in the picker would show a + button against a model that loads and
    // chats but silently can't see.
    final mmprojKey = ModelSource.parse(mmproj).cacheKey;
    final downloads = _FakeDownloadManager(isCached: (key) => key != mmprojKey);

    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(apiClient: fake, downloadManager: downloads),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<ModelInfo>));
    await tester.pumpAndSettle();
    expect(find.text('Gemma 3 4B (on-device)'), findsNothing);
  });

  // ------------------------------------------------- attachment input gating

  /// Pumps a chat screen whose picker holds [models], with the model named
  /// [select] chosen. Returns the fake attachment source driving the buttons.
  Future<_FakeAttachmentSource> pumpWithModel(
    WidgetTester tester,
    List<ModelInfo> models, {
    required String select,
    _FakeApiClient? api,
    bool micAllowed = true,
  }) async {
    _useDesktopSurface(tester);
    final source = _FakeAttachmentSource(micAllowed: micAllowed);
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(
        apiClient: api ?? _FakeApiClient(models),
        downloadManager: const _FakeDownloadManager(),
        attachmentSource: source,
      ),
    ));
    await tester.pumpAndSettle();

    // The picker defaults to the on-device model; switch to the one under test.
    await tester.tap(find.byType(DropdownButton<ModelInfo>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$select (local server)').last);
    await tester.pumpAndSettle();
    return source;
  }

  testWidgets('a text-only model offers neither the attach nor the mic button',
      (tester) async {
    await pumpWithModel(
      tester,
      const [ModelInfo(id: 'gpt2', name: 'GPT-2')],
      select: 'GPT-2',
    );

    expect(find.widgetWithIcon(IconButton, Icons.add), findsNothing);
    expect(find.widgetWithIcon(IconButton, Icons.mic_none), findsNothing);
  });

  testWidgets('an image-only model offers the attach button but not the mic',
      (tester) async {
    await pumpWithModel(
      tester,
      const [
        ModelInfo(
          id: 'ministral_3_3b',
          name: 'Ministral 3 3B',
          inputModalities: ['text', 'image'],
        ),
      ],
      select: 'Ministral 3 3B',
    );

    expect(find.widgetWithIcon(IconButton, Icons.add), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.mic_none), findsNothing);
  });

  testWidgets('an image+audio model offers both buttons', (tester) async {
    await pumpWithModel(
      tester,
      const [
        ModelInfo(
          id: 'gemma3n',
          name: 'Gemma 3n E2B',
          inputModalities: ['text', 'image', 'audio'],
        ),
      ],
      select: 'Gemma 3n E2B',
    );

    expect(find.widgetWithIcon(IconButton, Icons.add), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.mic_none), findsOneWidget);
  });

  testWidgets('a picked image is staged as a chip and sent with the message',
      (tester) async {
    final api = _FakeApiClient(const [
      ModelInfo(
        id: 'ministral_3_3b',
        name: 'Ministral 3 3B',
        inputModalities: ['text', 'image'],
      ),
    ]);
    final source = await pumpWithModel(
      tester,
      api.models,
      select: 'Ministral 3 3B',
      api: api,
    );

    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.pumpAndSettle();

    expect(source.pickCount, 1);
    expect(find.text('picked.png'), findsOneWidget);

    await tester.enterText(find.byType(TextField), "what's in this?");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    // Went out on the wire...
    expect(api.lastAttachments, hasLength(1));
    expect(api.lastAttachments.single.name, 'picked.png');
    expect(api.lastAttachments.single.kind, AttachmentKind.image);
    // ...and the staging strip cleared, so it can't be sent twice.
    expect(find.text('picked.png'), findsOneWidget); // now in the message bubble
  });

  testWidgets('the mic button toggles recording and stages the clip',
      (tester) async {
    final source = await pumpWithModel(
      tester,
      const [
        ModelInfo(
          id: 'gemma3n',
          name: 'Gemma 3n E2B',
          inputModalities: ['text', 'image', 'audio'],
        ),
      ],
      select: 'Gemma 3n E2B',
    );

    await tester.tap(find.widgetWithIcon(IconButton, Icons.mic_none));
    await tester.pumpAndSettle();

    expect(source.recording, isTrue);
    // Armed state: the button becomes a stop control and the hint changes.
    expect(find.widgetWithIcon(IconButton, Icons.stop_circle_outlined), findsOneWidget);
    expect(find.text('Recording…'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.stop_circle_outlined));
    await tester.pumpAndSettle();

    expect(source.recording, isFalse);
    expect(find.text('recording.wav'), findsOneWidget);
  });

  testWidgets('a denied microphone reports the problem instead of arming',
      (tester) async {
    final source = await pumpWithModel(
      tester,
      const [
        ModelInfo(
          id: 'gemma3n',
          name: 'Gemma 3n E2B',
          inputModalities: ['text', 'image', 'audio'],
        ),
      ],
      select: 'Gemma 3n E2B',
      micAllowed: false,
    );

    await tester.tap(find.widgetWithIcon(IconButton, Icons.mic_none));
    await tester.pumpAndSettle();

    expect(source.recording, isFalse);
    expect(find.text('Microphone access was denied.'), findsOneWidget);
    // Still the idle mic, never the armed stop control.
    expect(find.widgetWithIcon(IconButton, Icons.stop_circle_outlined), findsNothing);
  });

  testWidgets('switching to a text-only model drops staged attachments',
      (tester) async {
    final api = _FakeApiClient(const [
      ModelInfo(
        id: 'ministral_3_3b',
        name: 'Ministral 3 3B',
        inputModalities: ['text', 'image'],
      ),
      ModelInfo(id: 'gpt2', name: 'GPT-2'),
    ]);
    await pumpWithModel(tester, api.models, select: 'Ministral 3 3B', api: api);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('picked.png'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<ModelInfo>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPT-2 (local server)').last);
    await tester.pumpAndSettle();

    // Chip gone, attach button gone, and the user was told why.
    expect(find.text('picked.png'), findsNothing);
    expect(find.widgetWithIcon(IconButton, Icons.add), findsNothing);
    expect(find.textContaining('1 attachment removed'), findsOneWidget);
  });
}

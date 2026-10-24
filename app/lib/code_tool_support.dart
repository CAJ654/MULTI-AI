import 'on_device_engine.dart' show onDeviceModelId;

/// How likely a model is to work in the Code tab, which needs it to emit real
/// tool calls (read a file, edit, run a command) rather than describe them.
///
/// This is about how a model was trained and what chat template it ships, not
/// its size, so it is a per-model fact kept in one table here rather than
/// derived. The evidence behind every entry — what was tested, how, and what
/// was only inferred from a model's family — is in CODE-TAB-MODELS.md at the
/// repo root; keep the two in step.
enum CodeToolSupport { works, shouldWork, uncertain, unlikely }

class CodeToolVerdict {
  const CodeToolVerdict(this.support, this.detail, {required this.tested});

  final CodeToolSupport support;

  /// One or two sentences for the model's page: the result if [tested],
  /// otherwise why it is expected to behave this way.
  final String detail;

  /// True if the model itself was run and probed for tool calls; false if the
  /// verdict is inferred from its family.
  final bool tested;

  /// Short headline for the page. An untested negative says "unlikely" rather
  /// than "doesn't work", since nothing was actually run.
  String get label => switch (support) {
        CodeToolSupport.works => 'Works',
        CodeToolSupport.shouldWork => 'Should work',
        CodeToolSupport.uncertain => 'Uncertain',
        CodeToolSupport.unlikely => tested ? "Doesn't work" : 'Unlikely to work',
      };
}

/// The verdict for the roster model [id], or null for one that wasn't assessed
/// (external Colibri models, which the Code tab doesn't list, and anything new).
///
/// Accepts both id shapes: the on-device sibling of a model (`qwen3_8b_on_device`)
/// is the same weights as its server entry (`qwen3_8b`), so they share a verdict.
CodeToolVerdict? codeToolVerdictFor(String id) =>
    _verdicts[id.endsWith(_onDeviceSuffix) ? id.substring(0, id.length - _onDeviceSuffix.length) : id];

const _onDeviceSuffix = '_on_device';

final Map<String, CodeToolVerdict> _verdicts = _buildVerdicts();

Map<String, CodeToolVerdict> _buildVerdicts() {
  final verdicts = <String, CodeToolVerdict>{};
  void add(Iterable<String> ids, CodeToolSupport support, String detail, {bool tested = false}) {
    final verdict = CodeToolVerdict(support, detail, tested: tested);
    for (final id in ids) {
      verdicts[id] = verdict;
    }
  }

  // ---- Tested, and works
  add(
    const ['qwen3_0_6b', 'qwen3_1_7b', 'ministral_3_3b'],
    CodeToolSupport.works,
    'Returned a real tool call on all 5 of 5 test requests.',
    tested: true,
  );
  add(
    const ['gemma_4_e2b'],
    CodeToolSupport.works,
    'Returned a real tool call on all 5 of 5 test requests, and completed a '
    'full read-a-file turn through the Code tab.',
    tested: true,
  );
  add(
    const [onDeviceModelId],
    CodeToolSupport.works,
    'Returned a real tool call on all 5 of 5 test requests.',
    tested: true,
  );
  add(
    const ['falcon_3_1b'],
    CodeToolSupport.works,
    'Returned a real tool call on 4 of 5 test requests; once it wrote an empty '
    'tag as text instead. Expect occasional misses.',
    tested: true,
  );

  // ---- Not tested, expected to work
  add(
    const ['qwen3_4b', 'qwen3_8b', 'qwen3_14b', 'qwen3_32b', 'qwen3_30b_a3b'],
    CodeToolSupport.shouldWork,
    'Same family as Qwen3 0.6B and 1.7B, which were tested and call tools reliably.',
  );
  add(
    const ['gemma_4_e4b', 'gemma_4_12b', 'gemma_4_26b_a4b', 'gemma_4_31b'],
    CodeToolSupport.shouldWork,
    'Same chat template as Gemma 4 E2B, which was tested and calls tools reliably.',
  );
  add(
    const ['ministral_3_8b', 'ministral_3_14b'],
    CodeToolSupport.shouldWork,
    'Same family as Ministral 3 3B, which was tested and calls tools reliably.',
  );
  add(
    const ['mistral_7b', 'mistral_nemo_12b'],
    CodeToolSupport.shouldWork,
    'Ships a Mistral tool-calling template. An older design than Ministral 3, '
    'but built for it.',
  );
  add(
    const ['llama_3_2_3b', 'llama_3_1_8b'],
    CodeToolSupport.shouldWork,
    'Uses the Llama 3.1+ tool format. The 1B in this family was unreliable, so '
    'expect occasional misses.',
  );
  add(
    const ['falcon_3_3b', 'falcon_3_7b', 'falcon_3_10b'],
    CodeToolSupport.shouldWork,
    'Same family as Falcon3 1B, which got 4 of 5 in testing. Expect occasional misses.',
  );
  add(
    const ['gpt_oss_20b'],
    CodeToolSupport.shouldWork,
    'Built for native tool calling, but at about 12 GB it will not fit most GPUs '
    'without spilling to the CPU.',
  );

  // ---- Uncertain
  add(
    const ['llama_3_2_1b'],
    CodeToolSupport.uncertain,
    'Unreliable in testing: some requests returned a real tool call with '
    'mangled arguments, and then the server rejected one reply outright.',
    tested: true,
  );
  add(
    const ['qwen2_5_coder_14b', 'qwen2_5_coder_32b'],
    CodeToolSupport.uncertain,
    'The smaller Qwen2.5-Coder models fail at tool calling and these two were '
    'not tested, so they may or may not do better.',
  );
  add(
    const ['falcon_h1_1_5b', 'falcon_h1_3b', 'falcon_h1_7b', 'falcon_h1_34b'],
    CodeToolSupport.uncertain,
    'The 0.5B in this family failed testing and the larger ones were not tested.',
  );

  // ---- Unlikely / doesn't work
  add(
    const ['qwen2_5_coder_1_5b'],
    CodeToolSupport.unlikely,
    'Returned no real tool call on any of 5 test requests: it writes the call '
    'as text in an invented format. The Coder fine-tuning loses what the plain '
    'Qwen2.5 Instruct models can do.',
    tested: true,
  );
  add(
    const ['qwen2_5_coder_7b'],
    CodeToolSupport.unlikely,
    'Returned no real tool call in any test: it writes the call as text in an '
    'invented format, both when probed directly and in a full Code tab run. The '
    'Coder fine-tuning loses what the plain Qwen2.5 Instruct models can do.',
    tested: true,
  );
  add(
    const ['qwen2_5_coder_0_5b', 'qwen2_5_coder_3b'],
    CodeToolSupport.unlikely,
    'The 1.5B and 7B Qwen2.5-Coder models were tested and wrote their tool calls '
    'as text, so none ran. The Coder fine-tuning loses tool calling.',
  );
  add(
    const ['falcon_h1_0_5b'],
    CodeToolSupport.unlikely,
    'Returned no real tool call on any of 5 test requests: it writes correct-'
    'looking JSON as text, which is not recognised as a call.',
    tested: true,
  );
  add(
    const ['deepseek_r1_distill_1_5b'],
    CodeToolSupport.unlikely,
    'Returned no real tool call on any of 5 test requests; it says it cannot '
    'read files. R1 distills are not trained for function calling.',
    tested: true,
  );
  add(
    const [
      'deepseek_r1_distill_7b',
      'deepseek_r1_distill_14b',
      'deepseek_r1_distill_32b',
      'deepseek_r1_distill_llama_8b',
    ],
    CodeToolSupport.unlikely,
    'R1 distills are not trained for function calling; the 1.5B was tested and '
    'returned no tool call.',
  );
  add(
    const ['gemma_3_1b'],
    CodeToolSupport.unlikely,
    'Returned no real tool call on any of 5 test requests, and worse: it claims '
    'to have read the file and invents its contents. Its template has no tool support.',
    tested: true,
  );
  add(
    const ['gemma_3_270m', 'gemma_3_4b', 'gemma_3_12b', 'gemma_3_27b'],
    CodeToolSupport.unlikely,
    'The chat template has no tool support. The 1B in this family was tested and '
    'invents file contents instead of reading them.',
  );
  add(
    const ['codegemma_2b'],
    CodeToolSupport.unlikely,
    'Returned no real tool call on any of 5 test requests. A code-completion '
    'model with no chat or tool template.',
    tested: true,
  );
  add(
    const ['codegemma_7b'],
    CodeToolSupport.unlikely,
    'A code-completion model with no chat or tool template; the 2B was tested '
    'and returned no tool call.',
  );
  add(
    const [
      'gemma_3n_e2b',
      'gemma_3n_e4b',
      'gemma_1_2b',
      'gemma_1_7b',
      'gemma_2_2b',
      'gemma_2_9b',
      'gemma_2_27b',
      'medgemma_4b',
      'medgemma_1_5_4b',
      'medgemma_27b',
      'medgemma_27b_text',
      'txgemma_2b',
      'txgemma_9b',
      'txgemma_27b',
      'recurrentgemma_2b',
      'recurrentgemma_9b',
    ],
    CodeToolSupport.unlikely,
    'This Gemma generation has no tool support in its chat template.',
  );
  add(
    const ['llama_3_8b'],
    CodeToolSupport.unlikely,
    'Llama 3 (before 3.1) has no tool support in its chat template.',
  );
  add(
    const ['falcon2_11b', 'falcon_7b', 'falcon_mamba_7b'],
    CodeToolSupport.unlikely,
    'A base or older instruct model with no tool-calling template.',
  );

  return verdicts;
}

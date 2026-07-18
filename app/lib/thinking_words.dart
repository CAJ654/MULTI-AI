/// Phrase sets shown in the chat "thinking" row while a reply is generating,
/// grouped by the AI product that inspired them. Users pick which groups
/// (and which individual phrases within them) are in rotation via the
/// settings dialog in `chat_screen.dart` — see `thinking_settings.dart` for
/// the persisted enable/disable state.
class ThinkingWordGroup {
  const ThinkingWordGroup({required this.id, required this.label, required this.description, required this.words});

  final String id;
  final String label;
  final String description;
  final List<String> words;
}

const _classicVerbs = [
  'Accomplishing', 'Actioning', 'Actualizing', 'Architecting', 'Baking', 'Beaming', "Beboppin'",
  'Befuddling', 'Billowing', 'Blanching', 'Bloviating', 'Boogieing', 'Boondoggling', 'Booping',
  'Bootstrapping', 'Brewing', 'Burrowing', 'Calculating', 'Canoodling', 'Caramelizing', 'Cascading',
  'Catapulting', 'Cerebrating', 'Channeling', 'Channelling', 'Choreographing', 'Churning', 'Clauding',
  'Coalescing', 'Cogitating', 'Combobulating', 'Composing', 'Computing', 'Concocting', 'Considering',
  'Contemplating', 'Cooking', 'Crafting', 'Creating', 'Crunching', 'Crystallizing', 'Cultivating',
  'Deciphering', 'Deliberating', 'Determining', 'Dilly-dallying', 'Discombobulating', 'Doing', 'Doodling',
  'Drizzling', 'Ebbing', 'Effecting', 'Elucidating', 'Embellishing', 'Enchanting', 'Envisioning',
  'Evaporating', 'Fermenting', 'Fiddle-faddling', 'Finagling', 'Flambeing', 'Flibbertigibbeting',
  'Flowing', 'Flummoxing', 'Fluttering', 'Forging', 'Forming', 'Frolicking', 'Frosting', 'Gallivanting',
  'Galloping', 'Garnishing', 'Generating', 'Germinating', 'Gitifying', 'Grooving', 'Gusting',
  'Harmonizing', 'Hashing', 'Hatching', 'Herding', 'Honking', 'Hullaballooing', 'Hyperspacing',
  'Ideating', 'Imagining', 'Improvising', 'Incubating', 'Inferring', 'Infusing', 'Ionizing',
  'Jitterbugging', 'Julienning', 'Kneading', 'Leavening', 'Levitating', 'Lollygagging', 'Manifesting',
  'Marinating', 'Meandering', 'Metamorphosing', 'Misting', 'Moonwalking', 'Moseying', 'Mulling',
  'Mustering', 'Musing', 'Nebulizing', 'Nesting', 'Newspapering', 'Noodling', 'Nucleating', 'Orbiting',
  'Orchestrating', 'Osmosing', 'Perambulating', 'Percolating', 'Perusing', 'Philosophising',
  'Photosynthesizing', 'Pollinating', 'Pondering', 'Pontificating', 'Pouncing', 'Precipitating',
  'Prestidigitating', 'Processing', 'Proofing', 'Propagating', 'Puttering', 'Puzzling', 'Quantumizing',
  'Razzle-dazzling', 'Razzmatazzing', 'Recombobulating', 'Reticulating', 'Roosting', 'Ruminating',
  'Sauteing', 'Scampering', 'Schlepping', 'Scurrying', 'Seasoning', 'Shenaniganing', 'Shimmying',
  'Simmering', 'Skedaddling', 'Sketching', 'Slithering', 'Smooshing', 'Sock-hopping', 'Spelunking',
  'Spinning', 'Sprouting', 'Stewing', 'Sublimating', 'Swirling', 'Swooping', 'Symbioting',
  'Synthesizing', 'Tempering', 'Thinking', 'Thundering', 'Tinkering', 'Tomfoolering', 'Topsy-turvying',
  'Transfiguring', 'Transmuting', 'Twisting', 'Undulating', 'Unfurling', 'Unravelling', 'Vibing',
  'Waddling', 'Wandering', 'Warping', 'Whatchamacalliting', 'Whirlpooling', 'Whirring', 'Whisking',
  'Wibbling', 'Working', 'Wrangling', 'Zesting', 'Zigzagging',
];

/// Every group's `words` are fully-formatted display strings (own trailing
/// ellipsis), since some groups use gerund verbs and others full sentences.
final thinkingWordGroups = <ThinkingWordGroup>[
  ThinkingWordGroup(
    id: 'classic',
    label: 'Classic',
    description: 'Playful single-word verbs, in the spirit of Claude Code\'s own spinner.',
    words: [for (final v in _classicVerbs) '$v…'],
  ),
  const ThinkingWordGroup(
    id: 'devtools',
    label: 'Dev Tools',
    description: 'Build-step phrasing, in the spirit of frontend dev tool loaders.',
    words: [
      'Planning component layout…',
      'Generating Tailwind styles…',
      'Assembling React code…',
      'Rendering preview…',
    ],
  ),
  const ThinkingWordGroup(
    id: 'quirky',
    label: 'Quirky',
    description: 'Absurdist loading messages, in the spirit of The Sims, Slack, and Discord.',
    words: [
      'Reticulating splines…',
      'Generating emotional turbulence…',
      'Cajoling llamas…',
      'Rerouting power to warp drive…',
      'Knitting sweaters…',
      'Watering the digital plants…',
    ],
  ),
  const ThinkingWordGroup(
    id: 'transparency',
    label: 'Transparency Log',
    description:
        'Step-by-step status text, in the spirit of Perplexity\'s action log — references your actual '
        'question and the model answering it wherever it can (`{query}` / `{model}` placeholders).',
    words: [
      'Searching for "{query}"…',
      'Reading your question…',
      'Reading through the conversation so far…',
      'Cross-referencing "{query}"…',
      'Looking up what {model} knows…',
      'Retrieving relevant context…',
      'Synthesizing a reply with {model}…',
      'Drafting an answer to "{query}"…',
      'Checking the draft against your question…',
      'Weighing a couple of possible answers…',
      'Assembling {model}\'s response…',
      'Fact-checking the draft reply…',
      'Proofreading the final answer…',
    ],
  ),
];

/// Fills the `{query}`/`{model}` placeholders used by the Transparency Log
/// group's templates with live chat context. Called with real values while a
/// reply is generating (see `ThinkingIndicator`); called with no arguments to
/// render a generic preview in the settings dialog.
String fillThinkingTemplate(String template, {String? query, String? model}) {
  var result = template;
  if (result.contains('{query}')) {
    result = result.replaceAll('{query}', _truncateQuery(query));
  }
  if (result.contains('{model}')) {
    result = result.replaceAll('{model}', model?.trim().isNotEmpty == true ? model!.trim() : 'the model');
  }
  return result;
}

String _truncateQuery(String? query, {int maxLength = 40}) {
  final oneLine = query?.replaceAll('\n', ' ').trim();
  if (oneLine == null || oneLine.isEmpty) return 'your question';
  if (oneLine.length <= maxLength) return oneLine;
  return '${oneLine.substring(0, maxLength).trimRight()}…';
}

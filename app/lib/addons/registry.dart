import '../attachment_input.dart';
import 'addon.dart';
import 'chat/chat_addon.dart';
import 'code/code_addon.dart';
import 'components/component_manager.dart';
import 'components/components_addon.dart';
import 'models/models_addon.dart';
import 'orchestration/orchestration_addon.dart';

/// Every add-on this build ships. Adding a feature means adding one entry here
/// and one file — not editing the shell, the sidebar, or any of its neighbours.
///
/// A function rather than a const list on purpose: add-ons take injected
/// dependencies (tests supply fakes), and a later pass that reads presets off
/// disk needs somewhere to append the entries it finds. See the preset notes in
/// the plan.
List<AddOn> buildRegistry({
  AttachmentSource? attachmentSource,
  void Function(String url)? onMarkdownLinkTap,
  ComponentManager? componentManager,
}) {
  // Built once here (unless a test supplies its own) and handed to both Chat
  // and the Add-ons tab, so they observe the same live install/running state
  // with no HostCapability involved — see component_manager.dart's doc
  // comment on why that would be the wrong fit for something optional that
  // an essential tab (Chat) must keep working without.
  final components = componentManager ?? ComponentManager();
  return [
    const ModelsAddOn(),
    ChatAddOn(
      attachmentSource: attachmentSource,
      onMarkdownLinkTap: onMarkdownLinkTap,
      componentManager: components,
    ),
    OrchestrationAddOn(),
    CodeAddOn(),
    ComponentsAddOn(manager: components),
  ];
}

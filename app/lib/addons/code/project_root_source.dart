import 'package:file_picker/file_picker.dart';

/// Picks the project folder the Code tab's tools are scoped to.
///
/// Wrapped in an interface for the same reason as [AttachmentSource] in
/// `attachment_input.dart`: a real directory-picker dialog blocks under
/// `flutter test`, so [CodeAgentController] takes an injectable source and
/// tests supply a fake one that returns a temp directory instead.
abstract class ProjectRootSource {
  /// Returns the chosen absolute directory path, or null if the user
  /// cancelled the picker.
  Future<String?> pickDirectory();
}

class DefaultProjectRootSource implements ProjectRootSource {
  @override
  Future<String?> pickDirectory() =>
      FilePicker.getDirectoryPath(dialogTitle: 'Choose a project folder');
}

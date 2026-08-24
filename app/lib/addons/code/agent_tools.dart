import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

/// Names of tools whose effects reach outside the model's own reply — writing
/// or running something — and therefore need [ToolApprovalDecision] before
/// they execute. See `tool_approval.dart` and `code_agent_controller.dart`'s
/// `AgentHook.beforeToolCall`.
const gatedToolNames = {'write_file', 'edit_file', 'run_command'};

/// Largest file [readFile] will return in full. Past this, the content is
/// truncated with a note — an agent turn reading a multi-megabyte log
/// shouldn't blow the model's context budget silently.
const _maxReadBytes = 256 * 1024;

const _commandTimeout = Duration(seconds: 30);

/// Kills [process] and, on Windows, its whole descendant tree.
/// `Process.kill()` alone only signals the immediate child — with
/// `runInShell: true` that's `cmd.exe`, not the command it launched
/// underneath it, which would otherwise survive a kill unharmed.
Future<void> _killProcessTree(Process process) async {
  if (Platform.isWindows) {
    await Process.run('taskkill', ['/F', '/T', '/PID', '${process.pid}']);
  } else {
    process.kill(ProcessSignal.sigkill);
  }
}

/// Resolves [requestedPath] against [projectRoot] and rejects anything that
/// escapes it (`../../etc/passwd`-style traversal, or an absolute path
/// elsewhere on disk) before any tool touches the filesystem. This is a
/// correctness bound enforced for every path-taking tool, independent of and
/// prior to the write/run approval gate — reads are scoped by this too, not
/// just gated writes.
String resolveInRoot(String projectRoot, String requestedPath) {
  final root = p.normalize(p.absolute(projectRoot));
  final candidate = p.isAbsolute(requestedPath)
      ? requestedPath
      : p.join(root, requestedPath);
  final resolved = p.normalize(p.absolute(candidate));
  if (resolved != root && !p.isWithin(root, resolved)) {
    throw StateError(
      'Path "$requestedPath" resolves outside the project folder ($root) and was refused.',
    );
  }
  return resolved;
}

/// The Code tab's v1 tool set, scoped to [projectRoot]. `read_file`,
/// `list_dir`, and `glob_search` always proceed; `write_file`, `edit_file`,
/// and `run_command` (named in [gatedToolNames]) are executed here exactly
/// the same way — the approval gate lives one layer up, in the
/// [AgentHook.beforeToolCall] `CodeAgentController` installs, not in these
/// functions.
///
/// Every executable uses [ToolParameterMode.object]: dart_agent_core hands
/// the decoded JSON arguments straight through as a `Map`, which sidesteps
/// `Function.apply`'s positional/named-parameter ordering entirely — simpler
/// to get right for a hand-parsed tool-call tag than trusting argument order.
List<Tool> buildAgentTools({required String projectRoot}) => [
      _readFileTool(projectRoot),
      _listDirTool(projectRoot),
      _globSearchTool(projectRoot),
      _writeFileTool(projectRoot),
      _editFileTool(projectRoot),
      _runCommandTool(projectRoot),
    ];

Tool _readFileTool(String projectRoot) => Tool(
      name: 'read_file',
      description: 'Read the contents of a text file in the project.',
      parameterMode: ToolParameterMode.object,
      parameters: const {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'File path relative to the project root.',
          },
        },
        'required': ['path'],
      },
      executable: (Map<String, dynamic> args) async {
        final path = args['path'] as String? ?? '';
        final resolved = resolveInRoot(projectRoot, path);
        final file = File(resolved);
        if (!await file.exists()) {
          throw StateError('File not found: $path');
        }
        final bytes = await file.readAsBytes();
        final truncated = bytes.length > _maxReadBytes;
        final text = String.fromCharCodes(
          truncated ? bytes.sublist(0, _maxReadBytes) : bytes,
        );
        return truncated
            ? '$text\n\n[truncated — file is ${bytes.length} bytes, showing first $_maxReadBytes]'
            : text;
      },
    );

/// Lists the immediate (non-recursive) contents of [path] under
/// [projectRoot]. Shared by [_listDirTool] and
/// `CodeAgentController._describeProjectRoot`, which seeds a session's first
/// turn with the root listing so the model has baseline awareness of the
/// project without having to decide to call `list_dir` itself first — small
/// local models don't reliably make that call on their own for an open-ended
/// question like "tell me about this project".
Future<String> listDirectoryContents(String projectRoot, String path) async {
  final resolved = resolveInRoot(projectRoot, path);
  final dir = Directory(resolved);
  if (!await dir.exists()) {
    throw StateError('Directory not found: $path');
  }
  final entries = await dir.list().toList();
  entries.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  if (entries.isEmpty) return '(empty directory)';
  return entries
      .map((e) => '${e is Directory ? 'dir ' : 'file'}  ${p.basename(e.path)}')
      .join('\n');
}

Tool _listDirTool(String projectRoot) => Tool(
      name: 'list_dir',
      description: 'List files and subdirectories directly inside a project directory '
          '(non-recursive).',
      parameterMode: ToolParameterMode.object,
      parameters: const {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Directory path relative to the project root. Use "." for the root.',
          },
        },
        'required': ['path'],
      },
      executable: (Map<String, dynamic> args) async {
        final path = args['path'] as String? ?? '.';
        return listDirectoryContents(projectRoot, path);
      },
    );

Tool _globSearchTool(String projectRoot) => Tool(
      name: 'glob_search',
      description: 'Find files under the project matching a glob pattern, '
          'e.g. "**/*.dart" or "lib/*.dart".',
      parameterMode: ToolParameterMode.object,
      parameters: const {
        'type': 'object',
        'properties': {
          'pattern': {
            'type': 'string',
            'description': 'Glob pattern, relative to the project root.',
          },
        },
        'required': ['pattern'],
      },
      executable: (Map<String, dynamic> args) async {
        final pattern = args['pattern'] as String? ?? '';
        final root = p.normalize(p.absolute(projectRoot));
        final glob = Glob(pattern);
        final matches = await glob
            .list(root: root, followLinks: false)
            // Forward slashes regardless of host OS — the model sees this text
            // and a consistent separator is one less thing for a small model
            // to get wrong when it later passes a matched path to another tool.
            .map((entity) => p.relative(entity.path, from: root).replaceAll(r'\', '/'))
            .toList();
        matches.sort();
        return matches.isEmpty ? '(no matches)' : matches.join('\n');
      },
    );

Tool _writeFileTool(String projectRoot) => Tool(
      name: 'write_file',
      description: 'Create a file or overwrite it entirely with new content.',
      parameterMode: ToolParameterMode.object,
      parameters: const {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'File path relative to the project root.',
          },
          'content': {
            'type': 'string',
            'description': 'The full file content to write.',
          },
        },
        'required': ['path', 'content'],
      },
      executable: (Map<String, dynamic> args) async {
        final path = args['path'] as String? ?? '';
        final content = args['content'] as String? ?? '';
        final resolved = resolveInRoot(projectRoot, path);
        final file = File(resolved);
        await file.parent.create(recursive: true);
        await file.writeAsString(content);
        return 'Wrote ${content.length} characters to $path.';
      },
    );

Tool _editFileTool(String projectRoot) => Tool(
      name: 'edit_file',
      description: 'Replace one exact occurrence of old_string with new_string in a file. '
          'old_string must appear in the file exactly once.',
      parameterMode: ToolParameterMode.object,
      parameters: const {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'File path relative to the project root.',
          },
          'old_string': {
            'type': 'string',
            'description': 'The exact text to replace. Must match exactly once in the file.',
          },
          'new_string': {
            'type': 'string',
            'description': 'The text to replace it with.',
          },
        },
        'required': ['path', 'old_string', 'new_string'],
      },
      executable: (Map<String, dynamic> args) async {
        final path = args['path'] as String? ?? '';
        final oldString = args['old_string'] as String? ?? '';
        final newString = args['new_string'] as String? ?? '';
        final resolved = resolveInRoot(projectRoot, path);
        final file = File(resolved);
        if (!await file.exists()) {
          throw StateError('File not found: $path');
        }
        final content = await file.readAsString();
        final firstIndex = content.indexOf(oldString);
        if (firstIndex == -1) {
          throw StateError('old_string was not found in $path.');
        }
        final lastIndex = content.lastIndexOf(oldString);
        if (lastIndex != firstIndex) {
          throw StateError(
            'old_string appears more than once in $path — make it unique before editing.',
          );
        }
        final updated = content.replaceRange(
          firstIndex,
          firstIndex + oldString.length,
          newString,
        );
        await file.writeAsString(updated);
        return 'Edited $path.';
      },
    );

Tool _runCommandTool(String projectRoot) => Tool(
      name: 'run_command',
      description: 'Run a shell command in the project directory and return its output. '
          'Times out after ${_commandTimeout.inSeconds} seconds.',
      parameterMode: ToolParameterMode.object,
      parameters: const {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'The executable to run, e.g. "dart" or "git".',
          },
          'args': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Arguments to pass to the command.',
          },
        },
        'required': ['command'],
      },
      executable: (Map<String, dynamic> args) async {
        final command = args['command'] as String? ?? '';
        if (command.isEmpty) throw StateError('command must not be empty.');
        final commandArgs = (args['args'] as List?)?.cast<String>() ?? const [];
        final root = p.normalize(p.absolute(projectRoot));

        final process = await Process.start(
          command,
          commandArgs,
          workingDirectory: root,
          runInShell: true,
        );

        final stdoutBuf = StringBuffer();
        final stderrBuf = StringBuffer();
        final stdoutSub = process.stdout.transform(utf8.decoder).listen(stdoutBuf.write);
        final stderrSub = process.stderr.transform(utf8.decoder).listen(stderrBuf.write);

        int exitCode;
        try {
          try {
            exitCode = await process.exitCode.timeout(_commandTimeout);
          } on TimeoutException {
            // process.kill() only signals the immediate child — with
            // runInShell:true on Windows that's cmd.exe, not the command it
            // launched underneath it, so the real process would otherwise
            // survive the kill and keep the working directory locked.
            await _killProcessTree(process);
            // Best-effort wait for the tree to actually die before reporting
            // the timeout, so a caller that immediately cleans up the working
            // directory (e.g. deleting a temp project root) doesn't race a
            // handle that's still closing.
            await process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
            throw TimeoutException(
              'Command timed out after ${_commandTimeout.inSeconds}s and was killed.',
            );
          }
        } finally {
          await stdoutSub.cancel();
          await stderrSub.cancel();
        }

        final output = StringBuffer()
          ..writeln('exit code: $exitCode');
        if (stdoutBuf.isNotEmpty) output.writeln('stdout:\n$stdoutBuf');
        if (stderrBuf.isNotEmpty) output.writeln('stderr:\n$stderrBuf');
        return output.toString();
      },
    );

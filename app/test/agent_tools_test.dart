import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:multi_ai/addons/code/agent_tools.dart';

Future<dynamic> _call(List<Tool> tools, String name, Map<String, dynamic> args) {
  final tool = tools.firstWhere((t) => t.name == name);
  return (tool.executable as dynamic Function(Map<String, dynamic>))(args);
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('code_tab_tools_test');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('gatedToolNames names exactly the three tools that write or execute', () {
    expect(gatedToolNames, {'write_file', 'edit_file', 'run_command'});
  });

  group('read_file', () {
    test('reads an existing file', () async {
      await File('${root.path}/a.txt').writeAsString('hello');
      final tools = buildAgentTools(projectRoot: root.path);
      final result = await _call(tools, 'read_file', {'path': 'a.txt'});
      expect(result, 'hello');
    });

    test('throws a clear error for a missing file', () async {
      final tools = buildAgentTools(projectRoot: root.path);
      expect(
        () => _call(tools, 'read_file', {'path': 'missing.txt'}),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('not found'))),
      );
    });

    test('refuses a path that escapes the project root', () async {
      final tools = buildAgentTools(projectRoot: root.path);
      expect(
        () => _call(tools, 'read_file', {'path': '../../etc/passwd'}),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('outside the project folder'))),
      );
    });

    test('refuses an absolute path outside the root', () async {
      final tools = buildAgentTools(projectRoot: root.path);
      final outside = await Directory.systemTemp.createTemp('code_tab_outside');
      try {
        final outsideFile = File('${outside.path}/secret.txt')..writeAsStringSync('nope');
        expect(
          () => _call(tools, 'read_file', {'path': outsideFile.path}),
          throwsA(isA<StateError>()),
        );
      } finally {
        await outside.delete(recursive: true);
      }
    });
  });

  group('list_dir', () {
    test('lists files and subdirectories non-recursively', () async {
      await File('${root.path}/a.txt').create();
      await Directory('${root.path}/sub').create();
      await File('${root.path}/sub/nested.txt').create();

      final tools = buildAgentTools(projectRoot: root.path);
      final result = await _call(tools, 'list_dir', {'path': '.'}) as String;

      expect(result, contains('a.txt'));
      expect(result, contains('sub'));
      expect(result, isNot(contains('nested.txt')));
    });

    test('reports an empty directory distinctly', () async {
      final tools = buildAgentTools(projectRoot: root.path);
      final result = await _call(tools, 'list_dir', {'path': '.'});
      expect(result, '(empty directory)');
    });
  });

  group('glob_search', () {
    test('finds nested matches recursively for **', () async {
      await Directory('${root.path}/lib').create();
      await File('${root.path}/lib/a.dart').create();
      await File('${root.path}/lib/b.txt').create();
      await Directory('${root.path}/lib/sub').create();
      await File('${root.path}/lib/sub/c.dart').create();

      final tools = buildAgentTools(projectRoot: root.path);
      final result = await _call(tools, 'glob_search', {'pattern': '**/*.dart'}) as String;
      final matches = result.split('\n');

      expect(matches, containsAll(['lib/a.dart', 'lib/sub/c.dart']));
      expect(result, isNot(contains('b.txt')));
    });
  });

  group('write_file', () {
    test('creates a new file, including parent directories', () async {
      final tools = buildAgentTools(projectRoot: root.path);
      await _call(tools, 'write_file', {'path': 'a/b/c.txt', 'content': 'hi'});
      expect(await File('${root.path}/a/b/c.txt').readAsString(), 'hi');
    });

    test('overwrites an existing file entirely', () async {
      final file = File('${root.path}/a.txt')..writeAsStringSync('old');
      final tools = buildAgentTools(projectRoot: root.path);
      await _call(tools, 'write_file', {'path': 'a.txt', 'content': 'new'});
      expect(await file.readAsString(), 'new');
    });

    test('refuses to write outside the project root', () async {
      final tools = buildAgentTools(projectRoot: root.path);
      expect(
        () => _call(tools, 'write_file', {'path': '../escape.txt', 'content': 'x'}),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('edit_file', () {
    test('replaces the single occurrence of old_string', () async {
      final file = File('${root.path}/a.txt')..writeAsStringSync('hello world');
      final tools = buildAgentTools(projectRoot: root.path);
      await _call(tools, 'edit_file', {
        'path': 'a.txt',
        'old_string': 'world',
        'new_string': 'there',
      });
      expect(await file.readAsString(), 'hello there');
    });

    test('refuses when old_string is not found', () async {
      File('${root.path}/a.txt').writeAsStringSync('hello world');
      final tools = buildAgentTools(projectRoot: root.path);
      expect(
        () => _call(tools, 'edit_file',
            {'path': 'a.txt', 'old_string': 'nope', 'new_string': 'x'}),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('not found'))),
      );
    });

    test('refuses when old_string is ambiguous', () async {
      File('${root.path}/a.txt').writeAsStringSync('foo foo');
      final tools = buildAgentTools(projectRoot: root.path);
      expect(
        () => _call(
            tools, 'edit_file', {'path': 'a.txt', 'old_string': 'foo', 'new_string': 'bar'}),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('more than once'))),
      );
    });
  });

  group('run_command', () {
    test('captures stdout and a zero exit code', () async {
      final tools = buildAgentTools(projectRoot: root.path);
      final isWindows = Platform.isWindows;
      final result = await _call(
        tools,
        'run_command',
        isWindows
            ? {'command': 'cmd', 'args': ['/c', 'echo hello']}
            : {'command': 'echo', 'args': ['hello']},
      ) as String;
      expect(result, contains('exit code: 0'));
      expect(result, contains('hello'));
    });

    test('runs with the project root as the working directory', () async {
      await File('${root.path}/marker.txt').create();
      final tools = buildAgentTools(projectRoot: root.path);
      final isWindows = Platform.isWindows;
      final result = await _call(
        tools,
        'run_command',
        isWindows ? {'command': 'cmd', 'args': ['/c', 'dir', '/b']} : {'command': 'ls'},
      ) as String;
      expect(result, contains('marker.txt'));
    });

    test('times out and kills a long-running command', () async {
      final tools = buildAgentTools(projectRoot: root.path);
      final isWindows = Platform.isWindows;
      await expectLater(
        _call(
          tools,
          'run_command',
          isWindows
              ? {'command': 'ping', 'args': ['127.0.0.1', '-n', '60']}
              : {'command': 'sleep', 'args': ['60']},
        ),
        throwsA(isA<Object>()),
      );
    }, timeout: const Timeout(Duration(seconds: 40)));
  });

  test('resolveInRoot allows the root itself', () {
    expect(FileSystemEntity.identicalSync(resolveInRoot(root.path, '.'), root.path), isTrue);
  });
}

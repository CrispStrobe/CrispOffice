@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/src/archive_directory_native.dart';
import 'package:test/test.dart';

List<MailArchiveDirectoryEntry> _files(
  List<MailArchiveDirectoryEntry> entries,
) => entries
    .where((entry) => entry.outcome == MailArchiveDirectoryOutcome.file)
    .toList();

void main() {
  late Directory directory;

  setUp(() async {
    // Resolve the system temporary directory once: macOS commonly exposes /tmp
    // through a link, which the production enumerator deliberately rejects.
    final temporary = await Directory.systemTemp.resolveSymbolicLinks();
    directory = await Directory(temporary).createTemp('mail-directory-test-');
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  Future<File> write(String relative, [int bytes = 1]) async {
    final file = File(p.join(directory.path, relative));
    await file.parent.create(recursive: true);
    return file.writeAsBytes(List<int>.filled(bytes, 65));
  }

  test(
    'empty root has one inspected entry and an explicit completion',
    () async {
      final entries = await enumerateMailArchiveDirectory(directory).toList();
      expect(entries.map((entry) => entry.outcome), [
        MailArchiveDirectoryOutcome.directory,
        MailArchiveDirectoryOutcome.completed,
      ]);
      expect(entries.last.terminal, isTrue);
      final progress = entries.last.progress;
      expect(progress.entriesInspected, 1);
      expect(progress.directoriesVisited, 1);
      expect(progress.filesAccepted, 0);
      expect(progress.acceptedBytes, 0);
      expect(progress.errorEntries, 0);
    },
  );

  test('files carry exact independent portable folder provenance', () async {
    await write('Inbox/message.EML', 3);
    await write('Sent/message.eml', 5);
    await write('Sent/2026/collected.MbOx', 7);
    await write('at-root.eml', 2);
    final entries = await enumerateMailArchiveDirectory(directory).toList();
    final files = _files(entries);
    expect(files.map((entry) => entry.relativePath).toSet(), {
      'Inbox/message.EML',
      'Sent/message.eml',
      'Sent/2026/collected.MbOx',
      'at-root.eml',
    });
    expect(
      {for (final entry in files) entry.relativePath: entry.relativeFolder},
      {
        'Inbox/message.EML': 'Inbox',
        'Sent/message.eml': 'Sent',
        'Sent/2026/collected.MbOx': 'Sent/2026',
        'at-root.eml': '',
      },
    );
    for (final entry in files) {
      expect(p.isAbsolute(entry.absolutePath!), isTrue);
      expect(p.isWithin(directory.path, entry.absolutePath!), isTrue);
      expect(await File(entry.absolutePath!).length(), entry.byteLength);
    }
    expect(
      files.singleWhere((entry) => entry.relativePath!.endsWith('.MbOx')).kind,
      MailArchiveDirectoryFileKind.mbox,
    );
    expect(entries.last.progress.filesAccepted, 4);
    expect(entries.last.progress.acceptedBytes, 17);
    expect(entries.last.progress.entriesInspected, 8);
    expect(entries.last.progress.directoriesVisited, 4);
  });

  test(
    'unsupported files are visible and do not stop supported files',
    () async {
      await write('mail.eml');
      await write('readme.txt', 10);
      await write('no-extension', 20);
      final entries = await enumerateMailArchiveDirectory(directory).toList();
      expect(_files(entries).single.relativePath, 'mail.eml');
      expect(
        entries.where(
          (entry) => entry.issue == MailArchiveDirectoryIssue.unsupportedFile,
        ),
        hasLength(2),
      );
      expect(entries.last.progress.entriesInspected, 4);
      expect(entries.last.progress.skippedEntries, 2);
      expect(entries.last.progress.acceptedBytes, 1);
      expect(entries.last.outcome, MailArchiveDirectoryOutcome.completed);
    },
  );

  test('nonrecursive mode explicitly skips child directories', () async {
    await write('root.eml');
    await write('child/nested.eml');
    final entries = await enumerateMailArchiveDirectory(
      directory,
      recursive: false,
    ).toList();
    expect(_files(entries).single.relativePath, 'root.eml');
    expect(
      entries
          .singleWhere(
            (entry) =>
                entry.issue == MailArchiveDirectoryIssue.recursionDisabled,
          )
          .relativePath,
      'child',
    );
    expect(entries.last.progress.entriesInspected, 3);
    expect(entries.last.progress.skippedEntries, 1);
  });

  test('depth cap rejects a subtree and preserves allowed siblings', () async {
    await write('direct.eml');
    await write('one/allowed.eml');
    await write('one/two/unvisited.eml');
    final entries = await enumerateMailArchiveDirectory(
      directory,
      limits: const MailArchiveDirectoryLimits(maxDepth: 1),
    ).toList();
    expect(_files(entries).map((entry) => entry.relativePath).toSet(), {
      'direct.eml',
      'one/allowed.eml',
    });
    final limited = entries.singleWhere(
      (entry) => entry.issue == MailArchiveDirectoryIssue.depthLimit,
    );
    expect(limited.relativePath, 'one/two');
    expect(limited.terminal, isFalse);
    expect(entries.last.progress.entriesInspected, 5);
    expect(entries.last.progress.limitedEntries, 1);
  });

  test('open iterator budget is checked before descending', () async {
    await write('direct.eml');
    await write('child/unvisited.eml');
    final entries = await enumerateMailArchiveDirectory(
      directory,
      limits: const MailArchiveDirectoryLimits(maxPendingDirectories: 1),
    ).toList();
    expect(_files(entries).single.relativePath, 'direct.eml');
    expect(
      entries
          .singleWhere(
            (entry) =>
                entry.issue == MailArchiveDirectoryIssue.pendingDirectoryLimit,
          )
          .relativePath,
      'child',
    );
    expect(entries.last.progress.directoriesVisited, 1);
  });

  test('entry budget counts root, unsupported files and directories', () async {
    await write('unsupported.txt');
    await write('empty/another.txt');
    await write('mail.eml');
    final entries = await enumerateMailArchiveDirectory(
      directory,
      limits: const MailArchiveDirectoryLimits(maxEntries: 2),
    ).toList();
    expect(entries.last.issue, MailArchiveDirectoryIssue.entryLimit);
    expect(entries.last.terminal, isTrue);
    expect(entries.last.progress.entriesInspected, 2);
    expect(entries.last.progress.filesAccepted, lessThanOrEqualTo(1));
    expect(entries.where((entry) => entry.terminal), hasLength(1));
  });

  test(
    'exact entry budget can still report a fully scanned directory',
    () async {
      await write('mail.eml');
      final entries = await enumerateMailArchiveDirectory(
        directory,
        limits: const MailArchiveDirectoryLimits(maxEntries: 2),
      ).toList();
      expect(entries.last.outcome, MailArchiveDirectoryOutcome.completed);
      expect(entries.last.progress.entriesInspected, 2);
    },
  );

  test('file cap stops before accepting an excess file', () async {
    await write('one.eml');
    await write('two.mbox');
    final entries = await enumerateMailArchiveDirectory(
      directory,
      limits: const MailArchiveDirectoryLimits(maxFiles: 1),
    ).toList();
    expect(_files(entries), hasLength(1));
    expect(entries.last.issue, MailArchiveDirectoryIssue.fileLimit);
    expect(entries.last.terminal, isTrue);
    expect(entries.last.progress.filesAccepted, 1);
    expect(entries.last.progress.acceptedBytes, 1);
  });

  test('zero file cap is a valid empty acceptance budget', () async {
    await write('one.eml');
    final entries = await enumerateMailArchiveDirectory(
      directory,
      limits: const MailArchiveDirectoryLimits(maxFiles: 0),
    ).toList();
    expect(_files(entries), isEmpty);
    expect(entries.last.issue, MailArchiveDirectoryIssue.fileLimit);
    expect(entries.last.progress.acceptedBytes, 0);
  });

  test('oversized EML is visible while MBOX remains streamable', () async {
    await write('oversized.eml', 5);
    await write('same-size.mbox', 5);
    await write('small.eml', 2);
    final entries = await enumerateMailArchiveDirectory(
      directory,
      limits: const MailArchiveDirectoryLimits(maxEmlBytes: 2),
    ).toList();
    expect(_files(entries).map((entry) => entry.relativePath).toSet(), {
      'same-size.mbox',
      'small.eml',
    });
    final limited = entries.singleWhere(
      (entry) => entry.issue == MailArchiveDirectoryIssue.emlBytesLimit,
    );
    expect(limited.byteLength, 5);
    expect(limited.terminal, isFalse);
    expect(entries.last.progress.acceptedBytes, 7);
    expect(entries.last.progress.limitedEntries, 1);
  });

  test(
    'aggregate byte budget stops without accepting oversized MBOX',
    () async {
      await write('large.mbox', 8);
      final entries = await enumerateMailArchiveDirectory(
        directory,
        limits: const MailArchiveDirectoryLimits(maxTotalFileBytes: 7),
      ).toList();
      expect(_files(entries), isEmpty);
      expect(entries.last.issue, MailArchiveDirectoryIssue.totalBytesLimit);
      expect(entries.last.byteLength, 8);
      expect(entries.last.progress.acceptedBytes, 0);
      expect(entries.last.terminal, isTrue);
    },
  );

  test('aggregate byte budget accepts an exact boundary', () async {
    await write('exact.mbox', 8);
    final entries = await enumerateMailArchiveDirectory(
      directory,
      limits: const MailArchiveDirectoryLimits(maxTotalFileBytes: 8),
    ).toList();
    expect(_files(entries), hasLength(1));
    expect(entries.last.outcome, MailArchiveDirectoryOutcome.completed);
    expect(entries.last.progress.acceptedBytes, 8);
  });

  test('zero byte budgets accept only an empty supported file', () async {
    await write('empty.eml', 0);
    final entries = await enumerateMailArchiveDirectory(
      directory,
      limits: const MailArchiveDirectoryLimits(
        maxTotalFileBytes: 0,
        maxEmlBytes: 0,
      ),
    ).toList();
    expect(_files(entries), hasLength(1));
    expect(entries.last.progress.acceptedBytes, 0);
  });

  test(
    'path budget rejects metadata before constructing a child path',
    () async {
      await write('long-filename.eml');
      final entries = await enumerateMailArchiveDirectory(
        directory,
        limits: MailArchiveDirectoryLimits(
          maxPathCodeUnits: directory.path.length + 3,
        ),
      ).toList();
      expect(_files(entries), isEmpty);
      final limited = entries.singleWhere(
        (entry) => entry.issue == MailArchiveDirectoryIssue.pathLimit,
      );
      expect(limited.absolutePath, isNull);
      expect(limited.relativePath, isNull);
      expect(limited.terminal, isFalse);
    },
  );

  test('root path budget fails before a walk starts', () async {
    final entries = await enumerateMailArchiveDirectory(
      directory,
      limits: const MailArchiveDirectoryLimits(maxPathCodeUnits: 1),
    ).toList();
    expect(entries.single.issue, MailArchiveDirectoryIssue.pathLimit);
    expect(entries.single.progress.entriesInspected, 0);
    expect(entries.single.terminal, isTrue);
  });

  test('root component budget fails before ancestor checks', () async {
    final entries = await enumerateMailArchiveDirectory(
      directory,
      limits: const MailArchiveDirectoryLimits(maxRootComponents: 1),
    ).toList();
    expect(entries.single.issue, MailArchiveDirectoryIssue.rootComponentLimit);
    expect(entries.single.progress.entriesInspected, 0);
  });

  final invalidLimits = <String, MailArchiveDirectoryLimits>{
    'entries': const MailArchiveDirectoryLimits(maxEntries: 0),
    'files': const MailArchiveDirectoryLimits(maxFiles: -1),
    'depth': const MailArchiveDirectoryLimits(maxDepth: -1),
    'iterators': const MailArchiveDirectoryLimits(maxPendingDirectories: 0),
    'total bytes': const MailArchiveDirectoryLimits(maxTotalFileBytes: -1),
    'EML bytes': const MailArchiveDirectoryLimits(maxEmlBytes: -1),
    'path': const MailArchiveDirectoryLimits(maxPathCodeUnits: 0),
    'root components': const MailArchiveDirectoryLimits(maxRootComponents: 0),
  };
  for (final invalid in invalidLimits.entries) {
    test(
      'invalid ${invalid.key} limit produces a sanitized terminal error',
      () async {
        final entries = await enumerateMailArchiveDirectory(
          directory,
          limits: invalid.value,
        ).toList();
        expect(entries.single.issue, MailArchiveDirectoryIssue.invalidLimits);
        expect(entries.single.terminal, isTrue);
        expect(entries.single.progress.entriesInspected, 0);
        expect(entries.single.toString(), isNot(contains(directory.path)));
      },
    );
  }

  test('cancelled token performs no filesystem inspection', () async {
    final cancellation = MailCancellationSource()..cancel();
    final entries = await enumerateMailArchiveDirectory(
      Directory(p.join(directory.path, 'missing-private-path')),
      cancellation: cancellation.token,
    ).toList();
    expect(entries.single.outcome, MailArchiveDirectoryOutcome.cancelled);
    expect(entries.single.progress.entriesInspected, 0);
    expect(entries.single.terminal, isTrue);
  });

  test('mid-walk cancellation preserves the accepted counters', () async {
    await write('one.eml', 3);
    await write('two.eml', 3);
    final cancellation = MailCancellationSource();
    final entries = <MailArchiveDirectoryEntry>[];
    await for (final entry in enumerateMailArchiveDirectory(
      directory,
      cancellation: cancellation.token,
    )) {
      entries.add(entry);
      if (entry.outcome == MailArchiveDirectoryOutcome.file) {
        cancellation.cancel();
      }
    }
    expect(_files(entries), hasLength(1));
    expect(entries.last.outcome, MailArchiveDirectoryOutcome.cancelled);
    expect(entries.last.progress.filesAccepted, 1);
    expect(entries.last.progress.acceptedBytes, 3);
    expect(entries.last.progress.entriesInspected, 2);
  });

  test('consumer cancellation releases open directory iterators', () async {
    await write('nested/mail.eml');
    final iterator = StreamIterator(enumerateMailArchiveDirectory(directory));
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.outcome, MailArchiveDirectoryOutcome.directory);
    await iterator.cancel();
    await directory.delete(recursive: true);
    expect(directory.existsSync(), isFalse);
  });

  test(
    'disappearing directories produce explicit errors without raw paths',
    () async {
      await write('child/unvisited.eml');
      final entries = <MailArchiveDirectoryEntry>[];
      await for (final entry in enumerateMailArchiveDirectory(directory)) {
        entries.add(entry);
        if (entry.outcome == MailArchiveDirectoryOutcome.directory &&
            entry.relativePath == 'child') {
          await Directory(entry.absolutePath!).delete(recursive: true);
        }
      }
      expect(_files(entries), isEmpty);
      final error = entries.singleWhere(
        (entry) => entry.outcome == MailArchiveDirectoryOutcome.error,
      );
      expect(error.issue, MailArchiveDirectoryIssue.inaccessible);
      expect(error.toString(), isNot(contains(directory.path)));
      expect(entries.last.progress.errorEntries, 1);
      expect(entries.last.outcome, MailArchiveDirectoryOutcome.completed);
    },
  );

  test('missing root and file roots have typed terminal errors', () async {
    final missing = await enumerateMailArchiveDirectory(
      Directory(p.join(directory.path, 'missing')),
    ).toList();
    expect(missing.single.issue, MailArchiveDirectoryIssue.inaccessible);
    expect(missing.single.terminal, isTrue);
    final file = await write('not-a-directory.eml');
    final notDirectory = await enumerateMailArchiveDirectory(
      Directory(file.path),
    ).toList();
    expect(
      notDirectory.single.issue,
      MailArchiveDirectoryIssue.rootNotDirectory,
    );
    expect(notDirectory.single.terminal, isTrue);
  });

  test('traversal root components are rejected before normalization', () async {
    final entries = await enumerateMailArchiveDirectory(
      Directory('${directory.path}${p.separator}..${p.separator}outside'),
    ).toList();
    expect(entries.single.issue, MailArchiveDirectoryIssue.invalidPath);
    expect(entries.single.progress.entriesInspected, 0);
  });

  test('invalid root control metadata is not exposed by the result', () async {
    final entries = await enumerateMailArchiveDirectory(
      Directory('${directory.path}\nprivate'),
    ).toList();
    expect(entries.single.issue, MailArchiveDirectoryIssue.invalidPath);
    expect(entries.single.relativePath, isNull);
    expect(entries.single.absolutePath, isNull);
    expect(entries.single.toString(), isNot(contains('private')));
  });

  if (!Platform.isWindows) {
    test(
      'links to files, directories and missing targets are never followed',
      () async {
        await write('real/mail.eml', 4);
        await Link(
          p.join(directory.path, 'linked.eml'),
        ).create(p.join(directory.path, 'real/mail.eml'));
        await Link(
          p.join(directory.path, 'linked-directory'),
        ).create(p.join(directory.path, 'real'));
        await Link(
          p.join(directory.path, 'missing.eml'),
        ).create(p.join(directory.path, 'nonexistent'));
        final entries = await enumerateMailArchiveDirectory(directory).toList();
        expect(_files(entries).single.relativePath, 'real/mail.eml');
        expect(
          entries.where(
            (entry) => entry.issue == MailArchiveDirectoryIssue.symbolicLink,
          ),
          hasLength(3),
        );
        expect(entries.last.progress.skippedEntries, 3);
        expect(entries.last.progress.acceptedBytes, 4);
      },
    );

    test('a selected root link is rejected', () async {
      await write('real/mail.eml');
      final link = Link(p.join(directory.path, 'root-link'));
      await link.create(p.join(directory.path, 'real'));
      final entries = await enumerateMailArchiveDirectory(
        Directory(link.path),
      ).toList();
      expect(entries.single.issue, MailArchiveDirectoryIssue.symbolicLink);
      expect(entries.single.terminal, isTrue);
      expect(entries.single.progress.filesAccepted, 0);
    });

    test('a link in a selected root ancestor is rejected', () async {
      await write('real/nested/mail.eml');
      final link = Link(p.join(directory.path, 'ancestor-link'));
      await link.create(p.join(directory.path, 'real'));
      final entries = await enumerateMailArchiveDirectory(
        Directory(p.join(link.path, 'nested')),
      ).toList();
      expect(entries.single.issue, MailArchiveDirectoryIssue.symbolicLink);
      expect(entries.single.terminal, isTrue);
    });

    test(
      'directory replacement by a link is caught before traversal',
      () async {
        await write('replace/mail.eml');
        final external = await Directory(
          directory.parent.path,
        ).createTemp('mail-external-');
        addTearDown(() => external.delete(recursive: true));
        await File(
          p.join(external.path, 'outside.eml'),
        ).writeAsString('outside');
        final entries = <MailArchiveDirectoryEntry>[];
        await for (final entry in enumerateMailArchiveDirectory(directory)) {
          entries.add(entry);
          if (entry.outcome == MailArchiveDirectoryOutcome.directory &&
              entry.relativePath == 'replace') {
            await Directory(entry.absolutePath!).delete(recursive: true);
            await Link(entry.absolutePath!).create(external.path);
          }
        }
        expect(_files(entries), isEmpty);
        expect(
          entries.where(
            (entry) => entry.issue == MailArchiveDirectoryIssue.symbolicLink,
          ),
          hasLength(1),
        );
        expect(
          await File(p.join(external.path, 'outside.eml')).readAsString(),
          'outside',
        );
      },
    );

    test(
      'backslash and control names are rejected without metadata rewriting',
      () async {
        await write('good/mail.eml');
        await write('bad\\folder/mail.eml');
        await write('bad\nfile.eml');
        final entries = await enumerateMailArchiveDirectory(directory).toList();
        expect(_files(entries).single.relativePath, 'good/mail.eml');
        final invalid = entries.where(
          (entry) => entry.issue == MailArchiveDirectoryIssue.invalidMetadata,
        );
        expect(invalid, hasLength(2));
        for (final entry in invalid) {
          expect(entry.relativePath, isNull);
          expect(entry.absolutePath, isNull);
        }
        expect(entries.last.progress.errorEntries, 2);
      },
    );

    test('named pipes are skipped without opening or reading them', () async {
      final result = await Process.run('mkfifo', [
        p.join(directory.path, 'pipe.eml'),
      ]);
      expect(result.exitCode, 0);
      final entries = await enumerateMailArchiveDirectory(
        directory,
      ).toList().timeout(const Duration(seconds: 5));
      expect(_files(entries), isEmpty);
      expect(
        entries
            .singleWhere(
              (entry) =>
                  entry.issue == MailArchiveDirectoryIssue.nonRegularFile,
            )
            .relativePath,
        'pipe.eml',
      );
    });
  }
}

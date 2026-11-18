/// Browser storage with explicit same-origin assets and durable storage only.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:drift/wasm.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:web/web.dart' as web;

import 'src/browser_setup.dart';
import 'src/errors.dart';
import 'src/models.dart';
import 'src/owner_locked_executor.dart';
import 'src/platform_configuration.dart';
import 'src/repository.dart';

export 'quds_mail_store.dart';

@JS('navigator.locks')
external web.LockManager? get _browserLocks;

/// Open a host/profile namespace in a durable browser virtual filesystem.
///
/// Hosts must serve the matching SQLite Wasm artifact and compiled
/// `tool/mail_store_worker.dart` themselves. Assets must share the page origin.
/// Web Locks ownership is required before any database migration or recovery.
/// This opener fails when durable safe storage is unavailable; it never falls
/// back to memory or to IndexedDB without cross-tab coordination.
Future<MailResult<SqliteMailRepository>> openBrowserMailStore({
  required MailProfileId profile,
  required String storageNamespace,
  required Uri sqlite3Uri,
  required Uri driftWorkerUri,
  MailStoreLimits limits = const MailStoreLimits(),
  DateTime Function()? clock,
  MailStoreFaultInjector? faultInjector,
}) async {
  _BrowserOwnerLease? lease;
  OwnerLockedMailExecutor? executor;
  try {
    if (!limits.isValid) {
      throw const MailStoreStorageException(MailProblemCode.invalidInput);
    }
    final wasmUri = mailStoreAssetUri(sqlite3Uri, baseUri: Uri.base);
    final workerUri = mailStoreAssetUri(driftWorkerUri, baseUri: Uri.base);
    final name =
        'quds_mail_${mailStoreNamespace(profile, namespace: storageNamespace)}';
    lease = await _BrowserOwnerLease.acquire('quds-mail-owner:$name');
    final probe = await WasmDatabase.probe(
      sqlite3Uri: wasmUri,
      driftWorkerUri: workerUri,
      databaseName: name,
    );
    final existing = probe.existingDatabases
        .where((entry) => entry.$2 == name)
        .map((entry) => entry.$1)
        .toSet();
    if (existing.length > 1) {
      throw const MailStoreStorageException(MailProblemCode.conflict);
    }
    final available = probe.availableStorages.where((storage) {
      return storage != WasmStorageImplementation.inMemory &&
          storage != WasmStorageImplementation.unsafeIndexedDb &&
          (existing.isEmpty || existing.contains(storage.storageApi));
    }).toList()..sort((a, b) => a.index.compareTo(b.index));
    if (available.isEmpty) {
      throw const MailStoreStorageException(MailProblemCode.unavailable);
    }
    final connection = await probe.open(
      available.first,
      name,
      localSetup: configureMailBrowserDatabase,
    );
    executor = OwnerLockedMailExecutor(connection, lease.release);
    final result = await SqliteMailRepository.open(
      executor: executor,
      profile: profile,
      limits: limits,
      clock: clock,
      faultInjector: faultInjector,
    );
    if (result is MailFailure<SqliteMailRepository>) await executor.close();
    return result;
  } catch (error) {
    try {
      if (executor != null) {
        await executor.close();
      } else {
        await lease?.release();
      }
    } catch (_) {
      // Return a content-free opening failure, not a raw browser exception.
    }
    return MailFailure(
      error is MailStoreStorageException
          ? mailStoreProblem(error)
          : const MailProblem(MailProblemCode.unavailable),
    );
  }
}

final class _BrowserOwnerLease {
  final Completer<JSAny?> _release = Completer<JSAny?>();
  late final Future<JSAny?> _request;

  static Future<_BrowserOwnerLease> acquire(String name) async {
    final locks = _browserLocks;
    if (locks == null) {
      throw const MailStoreStorageException(MailProblemCode.unavailable);
    }
    final acquired = Completer<_BrowserOwnerLease>();
    final lease = _BrowserOwnerLease();
    try {
      lease._request = locks
          .request(
            name,
            web.LockOptions(mode: 'exclusive', ifAvailable: true),
            ((web.Lock? lock) {
              if (lock == null) {
                acquired.completeError(
                  const MailStoreStorageException(MailProblemCode.conflict),
                );
                return Future<JSAny?>.value(null).toJS;
              }
              acquired.complete(lease);
              return lease._release.future.toJS;
            }).toJS,
          )
          .toDart;
      unawaited(
        lease._request.then<void>(
          (_) {
            if (!acquired.isCompleted) {
              acquired.completeError(
                const MailStoreStorageException(MailProblemCode.unavailable),
              );
            }
          },
          onError: (Object _, StackTrace _) {
            if (!acquired.isCompleted) {
              acquired.completeError(
                const MailStoreStorageException(MailProblemCode.unavailable),
              );
            }
          },
        ),
      );
    } catch (_) {
      throw const MailStoreStorageException(MailProblemCode.unavailable);
    }
    return acquired.future;
  }

  Future<void> release() async {
    if (!_release.isCompleted) _release.complete(null);
    try {
      await _request;
    } catch (_) {
      // Browser teardown must not expose its raw exception or retain ownership.
    }
  }
}

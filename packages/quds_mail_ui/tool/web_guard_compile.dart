// Compile-only entry for the browser runtime guard; not a browser test result.
import '../test/support/runtime_network_guard_web.dart';

Future<void> main() async {
  final guard = RuntimeNetworkGuard();
  await guard.run(() async {
    guard.probe();
  });
}

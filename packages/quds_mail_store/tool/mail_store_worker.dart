import 'package:drift/wasm.dart';
import 'package:quds_mail_store/src/browser_setup.dart';

void main() {
  WasmDatabase.workerMainForOpen(
    setupAllDatabases: configureMailBrowserDatabase,
  );
}

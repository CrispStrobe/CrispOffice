// Run the original incoming reconciliation suites in one compilation.
// Each group keeps its original hooks, fixtures, and assertions.
import 'package:flutter_test/flutter_test.dart';

import '../../../quds_mail_ui/test/body_presentation_test.dart' as suite14;
import '../../../quds_mail_ui/test/reader_theme_scroll_test.dart' as suite15;
import '../test/studio_credential_selection_race_test.dart' as suite1;
import '../test/studio_credential_selection_test.dart' as suite0;
import '../test/studio_downloads_capture_test.dart' as suite11;
import '../test/studio_downloads_layout_test.dart' as suite12;
import '../test/studio_downloads_manager_test.dart' as suite13;
import '../test/studio_layout_theme_test.dart' as suite10;
import '../test/studio_mail_account_catalog_test.dart' as suite4;
import '../test/studio_mail_account_stores_test.dart' as suite5;
import '../test/studio_mail_accounts_test.dart' as suite3;
import '../test/studio_mail_credentials_test.dart' as suite2;
import '../test/studio_mail_ews_test.dart' as suite8;
import '../test/studio_mail_reply_test.dart' as suite9;
import '../test/studio_mail_selected_store_integration_test.dart' as suite6;
import '../test/studio_mail_test.dart' as suite7;

void main() {
  group('studio_credential_selection_test.dart', suite0.main);
  group('studio_credential_selection_race_test.dart', suite1.main);
  group('studio_mail_credentials_test.dart', suite2.main);
  group('studio_mail_accounts_test.dart', suite3.main);
  group('studio_mail_account_catalog_test.dart', suite4.main);
  group('studio_mail_account_stores_test.dart', suite5.main);
  group('studio_mail_selected_store_integration_test.dart', suite6.main);
  group('studio_mail_test.dart', suite7.main);
  group('studio_mail_ews_test.dart', suite8.main);
  group('studio_mail_reply_test.dart', suite9.main);
  group('studio_layout_theme_test.dart', suite10.main);
  group('studio_downloads_capture_test.dart', suite11.main);
  group('studio_downloads_layout_test.dart', suite12.main);
  group('studio_downloads_manager_test.dart', suite13.main);
  group('body_presentation_test.dart', suite14.main);
  group('reader_theme_scroll_test.dart', suite15.main);
}

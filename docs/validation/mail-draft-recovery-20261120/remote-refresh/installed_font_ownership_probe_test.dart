import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

// Reproduces the registration call introduced by incoming commit 236850d3.
// This audit probe expects the observed rejection; it is not an acceptance
// claim for installed-font replacement. Existing bundled test bytes suffice
// because the ownership check rejects the family before reading those bytes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final spec in <(String, String, String)>[
    ('Arial', 'Liberation Sans', 'LiberationSans-Regular.ttf'),
    ('Times New Roman', 'Liberation Serif', 'LiberationSerif-Regular.ttf'),
    ('Courier New', 'Liberation Mono', 'LiberationMono-Regular.ttf'),
  ]) {
    test(
      'incoming installed ${spec.$1} call is refused after bundled registration',
      () async {
        await OfficeHostFonts.ensureRegistered();
        final previousRevision = OfficeHostFonts.registrationRevision;
        final bytes = await rootBundle.load(
          'packages/quds_office_editor/fonts/${spec.$3}',
        );
        await expectLater(
          OfficeHostFonts.registerFamily(
            family: spec.$1,
            faces: <ByteData>[bytes],
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Font alias is already registered to another family.',
            ),
          ),
        );
        expect(OfficeHostFonts.registeredFamily(spec.$1), spec.$2);
        expect(OfficeHostFonts.registrationRevision, previousRevision);
      },
    );
  }
}

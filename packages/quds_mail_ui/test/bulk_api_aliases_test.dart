import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

String _count(int shown, int loaded) => '$shown of $loaded';

MailMessageListStrings _strings({String? shown, String? visible}) =>
    MailMessageListStrings(
      searchLoaded: 'Search',
      unread: 'Unread',
      flagged: 'Flagged',
      noMessages: 'Empty',
      noMatches: 'No matches',
      loadMore: 'More',
      loading: 'Loading',
      loadedScope: 'Loaded',
      count: _count,
      selectShown: shown,
      selectVisible: visible,
    );

void main() {
  test('remote image candidate aliases agree by ordered URI values', () {
    final first = Uri.parse('https://images.example/first.png');
    final second = Uri.parse('https://images.example/second.png');
    MailReaderPresentation presentation(List<Uri> uris, List<Uri> urls) =>
        MailReaderPresentation(
          text: '',
          runs: const [],
          images: const [],
          diagnostics: const [],
          remoteImageUris: uris,
          remoteImageUrls: urls,
        );
    final result = presentation([first, second], [first, second]);
    expect(result.remoteImageUris, same(result.remoteImageUrls));
    expect(() => result.remoteImageUrls.clear(), throwsUnsupportedError);
    expect(() => presentation([first], [first, second]), throwsArgumentError);
    expect(
      () => presentation([first, second], [second, first]),
      throwsArgumentError,
    );
  });

  for (final useUris in [true, false]) {
    test('remote image alias useUris=$useUris retains a defensive copy', () {
      final source = [Uri.parse('https://images.example/first.png')];
      final result = MailReaderPresentation(
        text: '',
        runs: const [],
        images: const [],
        diagnostics: const [],
        remoteImageUris: useUris ? source : null,
        remoteImageUrls: useUris ? null : source,
      );
      source.clear();
      expect(result.remoteImageUris, [
        Uri.parse('https://images.example/first.png'),
      ]);
      expect(result.remoteImageUris, same(result.remoteImageUrls));
      expect(() => result.remoteImageUris.clear(), throwsUnsupportedError);
    });
  }

  test('published selection and enabled spellings expose one value', () {
    final scope = Object();
    final list = MailMessageList(
      items: const [],
      strings: _strings(),
      onOpen: (_) {},
      selectionRevision: scope,
      bulkEnabled: false,
    );
    expect(list.selectionScopeId, same(scope));
    expect(list.selectionRevision, same(scope));
    expect(list.bulkActionsEnabled, isFalse);
    expect(list.bulkEnabled, isFalse);
  });

  test('contradictory aliases fail before constructing a selection', () {
    expect(
      () => MailMessageList(
        items: const [],
        strings: _strings(),
        onOpen: (_) {},
        selectionScopeId: 'first',
        selectionRevision: 'second',
      ),
      throwsArgumentError,
    );
    expect(
      () => MailMessageList(
        items: const [],
        strings: _strings(),
        onOpen: (_) {},
        bulkActionsEnabled: true,
        bulkEnabled: false,
      ),
      throwsArgumentError,
    );
  });

  testWidgets('visible label alias supplies the rendered select-shown button', (
    tester,
  ) async {
    final strings = _strings(visible: 'Choose loaded');
    expect(strings.selectShown, 'Choose loaded');
    expect(strings.selectVisible, 'Choose loaded');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MailMessageList(
            items: const [
              MailMessageListItem(id: 'one', subject: 'Subject', sender: ''),
            ],
            strings: strings,
            onOpen: (_) {},
            onBulkAction: (_, _) {},
          ),
        ),
      ),
    );
    expect(find.text('Choose loaded'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mail-list-select-shown')),
      findsOneWidget,
    );
  });
}

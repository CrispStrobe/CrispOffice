import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_desktop_menu.dart';
import 'package:quds_office_studio/studio_window.dart';

Future<Object?> _nativeCall(
  WidgetTester tester,
  String channel,
  MethodCall call,
) async {
  const codec = StandardMethodCodec();
  final result = Completer<ByteData?>();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    channel,
    codec.encodeMethodCall(call),
    result.complete,
  );
  final ByteData? response = await result.future;
  return response == null ? null : codec.decodeEnvelope(response);
}

List<Map<Object?, Object?>> _items(Object? object) {
  if (object is Map<Object?, Object?>) {
    return <Map<Object?, Object?>>[
      if (object.containsKey('label')) object,
      for (final value in object.values) ..._items(value),
    ];
  }
  if (object is List<Object?>) {
    return <Map<Object?, Object?>>[
      for (final value in object) ..._items(value),
    ];
  }
  return <Map<Object?, Object?>>[];
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    StudioWindow.supported = false;
    StudioWindow.maximized = false;
    StudioWindow.fullscreen = false;
  });

  testWidgets(
    'desktop File menu invokes enabled actions and disables busy ones',
    (tester) async {
      int saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioFileMenu(
              label: 'File',
              groups: <List<StudioMenuAction>>[
                <StudioMenuAction>[
                  StudioMenuAction(
                    id: 'save',
                    label: 'Save',
                    icon: Icons.save_outlined,
                    shortcut: const SingleActivator(
                      LogicalKeyboardKey.keyS,
                      control: true,
                    ),
                    onSelected: () => saves++,
                  ),
                  const StudioMenuAction(
                    id: 'save-as',
                    label: 'Save As…',
                    icon: Icons.save_as_outlined,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('desktop-file-menu')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MenuItemButton>(
              find.byKey(const ValueKey('desktop-file-save-as')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('desktop-file-save')));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(find.byKey(const ValueKey('desktop-file-save')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'macOS menu serializes File shortcuts and dispatches native selection',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.menu,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.menu,
          null,
        ),
      );
      int savedAs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StudioNativeMenus(
            fileLabel: 'File',
            editLabel: 'Edit',
            viewLabel: 'View',
            windowLabel: 'Window',
            aboutLabel: 'About CrispOffice',
            settingsLabel: 'Settings…',
            fileGroups: <List<StudioMenuAction>>[
              <StudioMenuAction>[
                StudioMenuAction(
                  id: 'save-as',
                  label: 'Save As…',
                  icon: Icons.save_as_outlined,
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: () => savedAs++,
                ),
                const StudioMenuAction(
                  id: 'open',
                  label: 'Open…',
                  icon: Icons.folder_open,
                ),
              ],
            ],
            editGroups: const <List<StudioMenuAction>>[],
            onAbout: () {},
            onSettings: () {},
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      final data = calls
          .lastWhere((call) => call.method == 'Menu.setMenus')
          .arguments;
      final items = _items(data);
      expect(
        items.map((item) => item['label']),
        containsAll(<String>[
          'CrispOffice',
          'File',
          'Save As…',
          'Open…',
          'Edit',
          'View',
          'Window',
        ]),
      );
      final saveAs = items.singleWhere((item) => item['label'] == 'Save As…');
      final open = items.singleWhere((item) => item['label'] == 'Open…');
      expect(saveAs['enabled'], isTrue);
      expect(open['enabled'], isFalse);
      expect(saveAs['shortcutTrigger'], isNotNull);
      expect(saveAs['shortcutModifiers'], isNotNull);
      await _nativeCall(
        tester,
        'flutter/menu',
        MethodCall('Menu.selectedCallback', saveAs['id']),
      );
      expect(savedAs, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'native Quit waits for and respects the workspace close decision',
    (tester) async {
      bool allow = false;
      int requests = 0;
      await tester.pumpWidget(
        StudioWindowScope(
          onChanged: () {},
          onCloseRequested: () async {
            requests++;
            return allow;
          },
          child: const SizedBox(),
        ),
      );
      expect(
        await _nativeCall(
          tester,
          'crispoffice/window',
          const MethodCall('confirmQuit'),
        ),
        isFalse,
      );
      allow = true;
      expect(
        await _nativeCall(
          tester,
          'crispoffice/window',
          const MethodCall('confirmQuit'),
        ),
        isTrue,
      );
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('macOS Close restores prevention and synchronizes fullscreen', (
    tester,
  ) async {
    StudioWindow.supported = true;
    final calls = <MethodCall>[];
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    bool allow = false;
    int changes = 0;
    await tester.pumpWidget(
      StudioWindowScope(
        onChanged: () {
          changes++;
        },
        onCloseRequested: () async => allow,
        child: const SizedBox(),
      ),
    );
    await _nativeCall(
      tester,
      'window_manager',
      const MethodCall('onEvent', <String, Object?>{'eventName': 'close'}),
    );
    await tester.pump();
    expect(calls.where((call) => call.method == 'close'), isEmpty);
    allow = true;
    await _nativeCall(
      tester,
      'window_manager',
      const MethodCall('onEvent', <String, Object?>{'eventName': 'close'}),
    );
    await tester.pump();
    expect(calls.map((call) => call.method), <String>[
      'setPreventClose',
      'close',
      'setPreventClose',
    ]);
    expect(calls.first.arguments, <String, Object?>{'isPreventClose': false});
    expect(calls.last.arguments, <String, Object?>{'isPreventClose': true});
    await _nativeCall(
      tester,
      'window_manager',
      const MethodCall('onEvent', <String, Object?>{
        'eventName': 'enter-full-screen',
      }),
    );
    expect(StudioWindow.fullscreen, isTrue);
    await _nativeCall(
      tester,
      'window_manager',
      const MethodCall('onEvent', <String, Object?>{
        'eventName': 'leave-full-screen',
      }),
    );
    expect(StudioWindow.fullscreen, isFalse);
    expect(changes, 2);
    expect(StudioWindow.usesNativeTrafficLights, isTrue);
    expect(StudioWindow.usesCaptionButtons, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

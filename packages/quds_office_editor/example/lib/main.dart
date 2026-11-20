import 'package:flutter/material.dart';

import 'sample_library.dart';
import 'studio_data_root.dart';
import 'studio_fonts.dart';
import 'studio_licenses.dart';
import 'studio_window.dart';
import 'suite_workspace.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerStudioLicenses();
  await initializeStudioDataRoot();
  await StudioWindow.bootstrap();
  await StudioFonts.register();
  await SampleLibrary.preload();
  runApp(const QudsOfficeStudioApp());
}

class QudsOfficeStudioApp extends StatelessWidget {
  const QudsOfficeStudioApp({super.key, this.home});

  /// The workspace to show; defaults to the ordinary [SuiteWorkspace].
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CrispOffice',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Liberation Sans',
        fontFamilyFallback: const <String>['Noto Naskh Arabic', 'Tajawal'],
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B579A)),
      ),
      builder: (BuildContext context, Widget? child) {
        return StudioWindow.wrap(child ?? const SizedBox.shrink());
      },
      home: home ?? const SuiteWorkspace(),
    );
  }
}

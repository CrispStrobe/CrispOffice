import 'package:flutter/material.dart';
import 'package:quds_office_studio/studio_mail.dart';
import 'package:quds_office_studio/studio_strings.dart';

/// Compile the public Mail entry through Flutter's actual browser libraries.
/// This probe verifies the conditional web import graph; it does not claim a
/// running browser session, plugin interaction, or deployed application build.
void main() {
  runApp(
    const MaterialApp(
      home: StudioMailDialog(strings: StudioStrings(StudioLanguage.en)),
    ),
  );
}

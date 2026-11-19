import 'package:flutter/material.dart';

import 'studio_saved_mail.dart';
import 'studio_strings.dart';

/// Browser Mail reads user-selected files without importing native sockets.
class StudioMailDialog extends StatelessWidget {
  const StudioMailDialog({super.key, required this.strings});

  final StudioStrings strings;

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: StudioSavedMailView(
      strings: strings,
      accountNotice: strings.mailAccountsUnavailable,
    ),
  );
}

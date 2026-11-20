import 'package:flutter/material.dart';

import 'studio_saved_mail.dart';
import 'studio_strings.dart';

/// Browser Mail reads user-selected files without importing native sockets.
class StudioMailDialog extends StatelessWidget {
  const StudioMailDialog({
    super.key,
    required this.strings,
    this.chromeBuilder,
  });

  final StudioStrings strings;
  final WidgetBuilder? chromeBuilder;

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Column(
      children: [
        if (chromeBuilder != null) chromeBuilder!(context),
        Expanded(
          child: StudioSavedMailView(
            strings: strings,
            accountNotice: strings.mailAccountsUnavailable,
          ),
        ),
      ],
    ),
  );
}

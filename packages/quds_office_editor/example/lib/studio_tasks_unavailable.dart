import 'package:flutter/widgets.dart';

import 'studio_strings.dart';

Widget buildStudioTasks(
  String title,
  VoidCallback close, {
  WidgetBuilder? chromeBuilder,
  VoidCallback? openConnections,
  bool compactRibbon = true,
  bool showCommandLabels = true,
  bool showGroupLabels = false,
  StudioLanguage language = StudioLanguage.en,
  ValueChanged<VoidCallback?>? registerNewItem,
}) => const SizedBox.shrink();

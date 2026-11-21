import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'studio_strings.dart';

/// The version and build number of the running app bundle.
///
/// On macOS/iOS these are `CFBundleShortVersionString`/`CFBundleVersion`, on
/// Android `versionName`/`versionCode`, and on the web Flutter's
/// `version.json`; all of them come from the pubspec `version` or the
/// `--build-name`/`--build-number` passed to `flutter build`.
@immutable
class StudioAppVersion {
  const StudioAppVersion(this.version, this.build);

  final String version;
  final String build;

  /// `1.2.3 (45)`, or just the version when there is no distinct build.
  String get label =>
      build.isEmpty || build == version ? version : '$version ($build)';

  @override
  bool operator ==(Object other) =>
      other is StudioAppVersion &&
      other.version == version &&
      other.build == build;

  @override
  int get hashCode => Object.hash(version, build);
}

/// Reads the version from the app bundle. Returns null when the platform
/// cannot report it (for example in a widget test without the plugin).
Future<StudioAppVersion?> loadStudioAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isEmpty) return null;
    return StudioAppVersion(info.version, info.buildNumber);
  } catch (_) {
    return null;
  }
}

Future<void> showStudioAbout(
  BuildContext context,
  StudioStrings strings, {
  StudioAppVersion? version,
}) => showDialog<void>(
  context: context,
  useRootNavigator: true,
  builder: (context) => StudioAboutDialog(strings: strings, version: version),
);

class StudioAboutDialog extends StatefulWidget {
  const StudioAboutDialog({
    super.key,
    required this.strings,
    this.version,
    this.versionLoader = loadStudioAppVersion,
  });

  final StudioStrings strings;

  /// The version to show. When null it is read once with [versionLoader];
  /// tests pass a fixed value so they stay deterministic.
  final StudioAppVersion? version;
  final Future<StudioAppVersion?> Function() versionLoader;

  @override
  State<StudioAboutDialog> createState() => _StudioAboutDialogState();
}

class _StudioAboutDialogState extends State<StudioAboutDialog> {
  StudioAppVersion? _loaded;

  StudioStrings get strings => widget.strings;
  StudioAppVersion? get _version => widget.version ?? _loaded;

  @override
  void initState() {
    super.initState();
    if (widget.version == null) {
      widget.versionLoader().then((value) {
        if (mounted && value != null) setState(() => _loaded = value);
      }, onError: (Object _) {});
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    // A capability query may be denied even when the browser accepts the URL.
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _sectionTitle(BuildContext context, String title) => Text(
    title,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.primary,
    ),
  );

  Widget _sectionText(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: SelectableText(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.info_outline),
          const SizedBox(width: 12),
          Text(strings.about),
        ],
      ),
      contentPadding: const EdgeInsets.all(24),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: Column(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'assets/branding/crispoffice_icon_512.png',
                        width: 96,
                        height: 96,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      strings.appTitle,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _version == null
                          ? ''
                          : '${strings.aboutVersion} ${_version!.label}',
                      key: const ValueKey<String>('studio-about-version'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      strings.aboutDescription,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              _sectionTitle(context, strings.serviceProvider),
              _sectionText(
                context,
                'Christian Ströbele\nNikolausstr. 5\n70190 Stuttgart\nDeutschland/Germany',
              ),
              const SizedBox(height: 16),
              _sectionTitle(context, strings.contact),
              _sectionText(
                context,
                'Email: postmaster@crispstro.be\nPhone: +49 176 6421 8601',
              ),
              const SizedBox(height: 16),
              _sectionTitle(context, strings.disclaimer),
              _sectionText(context, strings.disclaimerText),
              const SizedBox(height: 20),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  TextButton.icon(
                    icon: const Icon(Icons.code),
                    label: Text(strings.sourceCode),
                    onPressed: () => _launch(
                      'https://github.com/CrispStrobe/quds_office_suite',
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.web),
                    label: Text(strings.website),
                    onPressed: () => _launch('https://www.crispstro.be'),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.privacy_tip_outlined),
                    label: Text(strings.privacyPolicy),
                    onPressed: () => _launch(strings.privacyPolicyUrl),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.description),
                  label: Text(strings.viewLicences),
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: strings.appTitle,
                    applicationVersion: _version?.label,
                    applicationIcon: const Icon(
                      Icons.auto_awesome_mosaic,
                      size: 48,
                    ),
                    applicationLegalese: strings.legalNotice,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

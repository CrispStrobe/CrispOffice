import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'studio_strings.dart';

Future<void> showStudioAbout(BuildContext context, StudioStrings strings) =>
    showDialog<void>(
      context: context,
      builder: (context) => StudioAboutDialog(strings: strings),
    );

class StudioAboutDialog extends StatelessWidget {
  const StudioAboutDialog({super.key, required this.strings});

  final StudioStrings strings;

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
                      '${strings.aboutVersion} 1.0.0 (1)',
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
                    applicationVersion: '1.0.0',
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

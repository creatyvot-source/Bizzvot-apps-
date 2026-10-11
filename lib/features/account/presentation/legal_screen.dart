import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utilities/validators.dart';
import '../../../shared/widgets/state_views.dart';

/// Privacy, terms, analytics disclosure, support and open-source licences.
/// All links come from the server config so they can change without a release.
class LegalScreen extends ConsumerWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(currentConfigProvider);
    final version = ref.watch(appVersionProvider).value;

    Widget link(IconData icon, String title, String? url, {String? subtitle}) =>
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.open_in_new),
          enabled: url != null && Validators.isSafeWebUrl(url),
          onTap: () => launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & legal')),
      body: ContentWidth(
        child: ListView(
          children: [
            link(Icons.privacy_tip_outlined, 'Privacy policy', config.privacyPolicyUrl),
            link(Icons.gavel_outlined, 'Terms of service', config.termsUrl),
            link(
              Icons.insights_outlined,
              'Analytics & tracking disclosure',
              config.analyticsDisclosureUrl,
              subtitle: 'How card views and link taps are measured',
            ),
            if (config.supportEmail != null)
              ListTile(
                leading: const Icon(Icons.support_agent_outlined),
                title: const Text('Contact support'),
                subtitle: Text(config.supportEmail!),
                onTap: () => launchUrl(Uri(scheme: 'mailto', path: config.supportEmail)),
              ),
            if (config.supportPhone != null)
              ListTile(
                leading: const Icon(Icons.call_outlined),
                title: const Text('Call support'),
                subtitle: Text(config.supportPhone!),
                onTap: () => launchUrl(Uri(scheme: 'tel', path: config.supportPhone)),
              ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Open-source licences'),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Bizzvot',
                applicationVersion: version,
              ),
            ),
            if (version != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Version $version',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

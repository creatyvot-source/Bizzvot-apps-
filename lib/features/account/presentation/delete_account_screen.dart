import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/account_repository.dart';

/// In-app account deletion (App Store guideline 5.1.1(v)).
///
/// Owners delete their organization account after typing DELETE and
/// re-entering their password. Staff accounts are managed by the owner, so
/// staff see how to request removal instead.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _confirm = TextEditingController();
  final _password = TextEditingController();
  final _reason = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    _password.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await confirmAction(
      context,
      title: 'Delete account permanently?',
      message:
          'Your organization, staff logins, digital cards, reviews and '
          'analytics will be removed. Active subscriptions are cancelled. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(accountRepositoryProvider)
          .deleteAccount(password: _password.text, reason: _reason.text);
      if (!mounted) return;
      showMessage(context, 'Your account has been deleted.');
      await ref.read(sessionControllerProvider.notifier).logout();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final config = ref.watch(currentConfigProvider);
    final theme = Theme.of(context);

    if (user != null && !user.isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Delete account')),
        body: EmptyView(
          icon: Icons.manage_accounts_outlined,
          title: 'Your account is managed by your organization',
          message:
              'Ask your organization owner to remove you from Bizzvot. '
              'Removing you also deletes your staff login and card.'
              '${config.supportEmail != null ? '\n\nYou can also contact ${config.supportEmail}.' : ''}',
          action: config.supportEmail == null
              ? null
              : OutlinedButton.icon(
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Contact support'),
                  onPressed: () => launchUrl(
                    Uri(
                      scheme: 'mailto',
                      path: config.supportEmail,
                      queryParameters: {
                        'subject': 'Staff account deletion request',
                      },
                    ),
                  ),
                ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ContentWidth(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: AppSpacing.page,
            children: [
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: AppSpacing.page,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'Deleting your account removes your organization, all staff '
                          'logins and digital cards, reviews, analytics and saved '
                          'settings. Shared card links and QR codes stop working. '
                          'Invoices may be kept where the law requires it.',
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _reason,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Why are you leaving? (optional)',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Current password',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Enter your password to confirm'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _confirm,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Type DELETE to confirm',
                ),
                validator: (v) => v?.trim() == 'DELETE'
                    ? null
                    : 'Type DELETE in capital letters',
              ),
              const SizedBox(height: AppSpacing.lg),
              BusyButton(
                label: 'Delete my account',
                icon: Icons.delete_forever_outlined,
                onPressed: _confirm.text.trim() == 'DELETE' ? _delete : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

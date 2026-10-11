/// Build-time environment configuration.
///
/// Values are injected with `--dart-define`, e.g.
/// `flutter run --dart-define=BIZZVOT_ENV=staging`
/// `--dart-define=BIZZVOT_API_BASE=https://staging.api.bizzvot.com/api/v1`.
///
/// No secrets belong here: everything compiled into the app is public.
enum AppFlavor { development, staging, production }

class Env {
  const Env._({
    required this.flavor,
    required this.apiBaseUrl,
    required this.publicWebHost,
  });

  final AppFlavor flavor;

  /// Base URL of the REST API including the `/api/v1` prefix.
  final String apiBaseUrl;

  /// Host used to build shareable public card links: `https://<host>/card/<slug>`.
  final String publicWebHost;

  bool get isProduction => flavor == AppFlavor.production;

  static const _flavorName =
      String.fromEnvironment('BIZZVOT_ENV', defaultValue: 'development');
  static const _apiOverride = String.fromEnvironment('BIZZVOT_API_BASE');
  static const _webOverride = String.fromEnvironment('BIZZVOT_WEB_HOST');

  static final Env current = _resolve();

  static Env _resolve() {
    final flavor = switch (_flavorName) {
      'production' => AppFlavor.production,
      'staging' => AppFlavor.staging,
      _ => AppFlavor.development,
    };
    final (api, web) = switch (flavor) {
      AppFlavor.production => (
          'https://api.bizzvot.com/api/v1',
          'bizzvot.com',
        ),
      AppFlavor.staging => (
          'https://staging-api.bizzvot.com/api/v1',
          'staging.bizzvot.com',
        ),
      AppFlavor.development => (
          'http://10.0.2.2:5000/api/v1',
          'localhost:3000',
        ),
    };
    return Env._(
      flavor: flavor,
      apiBaseUrl: _apiOverride.isNotEmpty ? _apiOverride : api,
      publicWebHost: _webOverride.isNotEmpty ? _webOverride : web,
    );
  }

  /// Public share link for a card slug.
  String publicCardUrl(String slug) {
    final scheme = flavor == AppFlavor.development ? 'http' : 'https';
    return '$scheme://$publicWebHost/card/${Uri.encodeComponent(slug)}';
  }
}

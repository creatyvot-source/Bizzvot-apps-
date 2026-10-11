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

  /// Release builds default to production so a build without
  /// `--dart-define=BIZZVOT_ENV` can never ship pointing at a dev server.
  static const _flavorName = String.fromEnvironment(
    'BIZZVOT_ENV',
    defaultValue: bool.fromEnvironment('dart.vm.product') ? 'production' : 'development',
  );
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
      // The Bizzvot web portal (Coglink) serves the API on the same host.
      AppFlavor.production => (
          'https://www.bizzvot.com/api/v1',
          'www.bizzvot.com',
        ),
      // Staging host is not confirmed yet; override with
      // --dart-define=BIZZVOT_API_BASE / BIZZVOT_WEB_HOST.
      AppFlavor.staging => (
          'https://staging.bizzvot.com/api/v1',
          'staging.bizzvot.com',
        ),
      AppFlavor.development => (
          'http://10.0.2.2:3000/api/v1',
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

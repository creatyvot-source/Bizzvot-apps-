import 'package:bizzvot/core/config/app_config.dart';
import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/features/public_card/data/public_card_repository.dart';
import 'package:bizzvot/features/public_card/domain/public_directory.dart';
import 'package:bizzvot/features/public_card/presentation/public_directory_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

void main() {
  late FakePublicRepo repo;

  setUp(() => repo = FakePublicRepo());

  Future<void> pump(
    WidgetTester tester, {
    AppConfig config = AppConfig.defaults,
  }) async {
    await pumpTestApp(
      tester,
      const PublicDirectoryScreen(orgSlug: 'acme'),
      overrides: [
        publicCardRepositoryProvider.overrideWithValue(repo),
        currentConfigProvider.overrideWithValue(config),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the server list and opens a card', (tester) async {
    repo.onDirectory = (_, _) async => PublicDirectoryPage.fromJson({
      'organization': {'name': 'Acme Inc'},
      'items': [
        {'slug': 'ann', 'name': 'Ann Lee', 'designation': 'CEO'},
        {'slug': 'ben', 'name': 'Ben Ray'},
      ],
    });
    await pump(tester);

    expect(find.text('Acme Inc'), findsOneWidget);
    expect(find.text('Ann Lee'), findsOneWidget);
    expect(find.text('CEO'), findsOneWidget);
    expect(find.text('Ben Ray'), findsOneWidget);

    await tester.tap(find.text('Ben Ray'));
    await tester.pumpAndSettle();
    expect(find.text('route:/card/ben'), findsOneWidget);
  });

  testWidgets('404 shows the unavailable state', (tester) async {
    repo.onDirectory = (_, _) => Future.error(
      const AppException(AppErrorKind.notFound, 'Private', statusCode: 404),
    );
    await pump(tester);
    expect(find.text("This directory isn't available"), findsOneWidget);
    expect(find.text('Private'), findsNothing);
  });

  testWidgets('feature flag off: no request, unavailable state', (
    tester,
  ) async {
    var called = false;
    repo.onDirectory = (_, _) async {
      called = true;
      return const PublicDirectoryPage(entries: []);
    };
    await pump(
      tester,
      config: const AppConfig(features: {Flags.directory: false}),
    );
    expect(called, isFalse);
    expect(find.text("This directory isn't available"), findsOneWidget);
  });

  testWidgets('empty list shows an empty state', (tester) async {
    repo.onDirectory = (_, _) async => const PublicDirectoryPage(entries: []);
    await pump(tester);
    expect(find.text('No one is listed yet'), findsOneWidget);
  });
}

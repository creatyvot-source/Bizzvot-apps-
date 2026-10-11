import 'package:bizzvot/app/theme.dart';
import 'package:bizzvot/core/auth/session_controller.dart';
import 'package:bizzvot/core/utilities/json.dart';
import 'package:bizzvot/features/organization_profile/data/organization_profile_repository.dart';
import 'package:bizzvot/features/organization_profile/presentation/organization_profile_screen.dart';
import 'package:bizzvot/shared/models/organization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeProfileRepository implements OrganizationProfileRepository {
  FakeProfileRepository(this.doc);
  Json doc;
  final updates = <Json>[];

  /// Keys the fake "backend" persists (mirrors the real allow-list).
  static const allowed = {'name', 'logo', 'industry', 'address', 'gstNumber'};

  @override
  Future<OrganizationProfile> fetch() async => OrganizationProfile.fromJson(doc);

  @override
  Future<OrganizationProfile> update(Json changes) async {
    updates.add(changes);
    doc = {
      ...doc,
      for (final e in changes.entries)
        if (allowed.contains(e.key)) e.key: e.value,
    };
    return OrganizationProfile.fromJson(doc);
  }
}

Widget _app(FakeProfileRepository repo) => ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sessionKeyProvider.overrideWithValue('u1'),
        organizationProfileRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OrganizationProfileScreen(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester, FakeProfileRepository repo) async {
  await tester.pumpWidget(_app(repo));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  late FakeProfileRepository repo;
  setUp(() => repo = FakeProfileRepository({
        '_id': 'org1',
        'name': 'Acme',
        'industry': 'Real estate',
        'status': 'active',
      }));

  testWidgets('saves only the changed field', (tester) async {
    await _open(tester, repo);
    expect(find.text('No changes to save'), findsOneWidget);
    expect(find.text('Business email'), findsNothing); // unsupported by API

    await tester.enterText(find.widgetWithText(TextFormField, 'Organization name'), 'Acme Group');
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(FilledButton, 'Save changes'));

    expect(repo.updates, [
      {'name': 'Acme Group'},
    ]);
    expect(find.text('Profile saved'), findsOneWidget);
    expect(find.text('No changes to save'), findsOneWidget);
  });

  testWidgets('warns when the server ignores the directory setting', (tester) async {
    await _open(tester, repo);
    await _tap(tester, find.text('Show people directory'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Save changes'));

    expect(repo.updates.single, {'directoryVisibility': 'private'});
    expect(find.text('Directory setting not saved'), findsOneWidget);
  });

  testWidgets('asks before discarding unsaved edits', (tester) async {
    await _open(tester, repo);
    await tester.enterText(find.widgetWithText(TextFormField, 'Industry'), 'Retail');
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(repo.updates, isEmpty);
  });
}

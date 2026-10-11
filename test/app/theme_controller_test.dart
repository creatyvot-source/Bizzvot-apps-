import 'package:bizzvot/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemeStore & ThemeModeNotifier', () {
    test('MemoryThemeStore saves and loads', () async {
      final store = MemoryThemeStore();
      expect(await store.load(), isNull);

      await store.save(ThemeMode.dark);
      expect(await store.load(), ThemeMode.dark);

      await store.save(ThemeMode.light);
      expect(await store.load(), ThemeMode.light);
    });

    test('ThemeModeNotifier updates state and saves to store', () async {
      final store = MemoryThemeStore();
      final container = ProviderContainer(
        overrides: [
          themeStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);

      await container
          .read(themeModeProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(await store.load(), ThemeMode.dark);

      await container
          .read(themeModeProvider.notifier)
          .setThemeMode(ThemeMode.light);
      expect(container.read(themeModeProvider), ThemeMode.light);
      expect(await store.load(), ThemeMode.light);
    });
  });

  group('Theme widgets', () {
    testWidgets('ThemeToggleActionButton toggles between light and dark',
        (tester) async {
      final store = MemoryThemeStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themeStoreProvider.overrideWithValue(store),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              final mode = ref.watch(themeModeProvider);
              return MaterialApp(
                themeMode: mode,
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                home: const Scaffold(
                  appBar: PreferredSize(
                    preferredSize: Size.fromHeight(56),
                    child: ThemeToggleActionButton(),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = find.byKey(const Key('theme_toggle_action_button'));
      expect(button, findsOneWidget);

      // Tap to toggle
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(await store.load(), isNotNull);
    });

    testWidgets('ThemeModeSelector allows selecting System, Light, and Dark',
        (tester) async {
      final store = MemoryThemeStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themeStoreProvider.overrideWithValue(store),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              final mode = ref.watch(themeModeProvider);
              return MaterialApp(
                themeMode: mode,
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                home: const Scaffold(
                  body: ThemeModeSelector(),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('theme_mode_selector')), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      // Tap Dark
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(await store.load(), ThemeMode.dark);

      // Tap Light
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(await store.load(), ThemeMode.light);

      // Tap System
      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(await store.load(), ThemeMode.system);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'theme.dart';

/// Storage interface for user theme preference.
abstract interface class ThemeStore {
  Future<ThemeMode?> load();
  Future<void> save(ThemeMode mode);
}

class SecureThemeStore implements ThemeStore {
  SecureThemeStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;
  static const _key = 'bv.theme_mode';

  @override
  Future<ThemeMode?> load() async {
    try {
      final raw = await _storage.read(key: _key);
      return switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(ThemeMode mode) async {
    try {
      final val = switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
      await _storage.write(key: _key, value: val);
    } catch (_) {}
  }
}

class MemoryThemeStore implements ThemeStore {
  MemoryThemeStore([this._mode]);

  ThemeMode? _mode;

  @override
  Future<ThemeMode?> load() async => _mode;

  @override
  Future<void> save(ThemeMode mode) async {
    _mode = mode;
  }
}

final themeStoreProvider = Provider<ThemeStore>((ref) => SecureThemeStore());

class ThemeModeNotifier extends Notifier<ThemeMode> {
  bool _disposed = false;

  @override
  ThemeMode build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final saved = await ref.read(themeStoreProvider).load();
    if (saved != null && !_disposed) {
      state = saved;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await ref.read(themeStoreProvider).save(mode);
  }

  Future<void> toggle(BuildContext context) async {
    final currentBrightness = Theme.of(context).brightness;
    final next = currentBrightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    await setThemeMode(next);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// AppBar action button to quickly toggle between light and dark themes.
class ThemeToggleActionButton extends ConsumerWidget {
  const ThemeToggleActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      key: const Key('theme_toggle_action_button'),
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      ),
      onPressed: () {
        ref.read(themeModeProvider.notifier).toggle(context);
      },
    );
  }
}

/// Segmented button for choosing between System, Light, and Dark mode.
class ThemeModeSelector extends ConsumerWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: SegmentedButton<ThemeMode>(
        key: const Key('theme_mode_selector'),
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_outlined),
            label: Text('System'),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_outlined),
            label: Text('Light'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined),
            label: Text('Dark'),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (set) {
          if (set.isNotEmpty) {
            ref.read(themeModeProvider.notifier).setThemeMode(set.first);
          }
        },
      ),
    );
  }
}

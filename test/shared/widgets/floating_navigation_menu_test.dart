import 'package:bizzvot/app/theme.dart';
import 'package:bizzvot/shared/widgets/floating_navigation_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FloatingNavigationMenu displays items and responds to tap',
      (tester) async {
    int selected = 0;

    final items = const [
      FloatingNavItem(
        icon: Icons.space_dashboard_outlined,
        selectedIcon: Icons.space_dashboard,
        label: 'Dashboard',
      ),
      FloatingNavItem(
        icon: Icons.badge_outlined,
        selectedIcon: Icons.badge,
        label: 'Cards',
      ),
      FloatingNavItem(
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront,
        label: 'Shop',
      ),
      FloatingNavItem(
        icon: Icons.grid_view_outlined,
        selectedIcon: Icons.grid_view,
        label: 'More',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              bottomNavigationBar: FloatingNavigationMenu(
                selectedIndex: selected,
                onDestinationSelected: (i) {
                  setState(() => selected = i);
                },
                items: items,
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Cards'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    // Tap on Shop (index 2)
    await tester.tap(find.text('Shop'));
    await tester.pumpAndSettle();

    expect(selected, 2);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../cart_checkout_providers.dart';

/// App-bar cart action with a line-count badge.
class CartButton extends ConsumerWidget {
  const CartButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartCountProvider);
    final label = count == 0
        ? 'Cart, empty'
        : 'Cart, $count ${count == 1 ? 'item' : 'items'}';
    return IconButton(
      tooltip: label,
      onPressed: () => context.push(Routes.ownerCart),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: const Icon(Icons.shopping_bag_outlined),
      ),
    );
  }
}

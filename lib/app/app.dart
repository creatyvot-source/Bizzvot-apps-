import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/app_status/presentation/app_gate.dart';
import 'router.dart';
import 'theme.dart';

class BizzvotApp extends ConsumerWidget {
  const BizzvotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Bizzvot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
      builder: (context, child) => AppGate(child: child ?? const SizedBox.shrink()),
    );
  }
}

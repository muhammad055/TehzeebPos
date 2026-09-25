import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';

void main() {
  runApp(const ProviderScope(child: TehzeebApp()));
}

class TehzeebApp extends ConsumerWidget {
  const TehzeebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Tehzeeb POS',
      theme: buildAppTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth.dart';

/// Role-based shell. M0 only proves the gating; real screens land in M1+:
///   Owner   → Dashboard, Orders, Reports, Expenses (read), Menu
///   Manager → Dashboard-lite, Orders (+cancel), Purchases, Reports, Menu management
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider).valueOrNull;
    if (session == null) return const SizedBox.shrink();

    final isOwner = session.role == Role.owner;
    final title = isOwner ? 'Owner' : 'Manager';
    final sections = isOwner
        ? ['Dashboard', 'Orders', 'Reports', 'Expenses', 'Menu']
        : ['Dashboard', 'Orders', 'Purchases', 'Reports', 'Menu management'];

    return Scaffold(
      appBar: AppBar(
        title: Text('$title — ${session.username}'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: ListView(
        children: [
          for (final s in sections)
            ListTile(
              title: Text(s),
              subtitle: const Text('Coming in a later milestone'),
              enabled: false,
            ),
        ],
      ),
    );
  }
}

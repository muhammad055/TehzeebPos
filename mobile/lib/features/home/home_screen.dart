import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth.dart';
import '../dashboard/dashboard_screen.dart';

/// Role-based shell. The dashboard is live (M1); the other sections land in
/// later milestones:
///   Owner   → Dashboard, Orders, Reports, Expenses (read), Menu
///   Manager → Dashboard, Orders (+cancel), Purchases, Reports, Menu management
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider).valueOrNull;
    if (session == null) return const SizedBox.shrink();

    final isOwner = session.role == Role.owner;
    final title = isOwner ? 'Owner' : 'Manager';
    final upcoming = isOwner
        ? ['Orders', 'Reports', 'Expenses', 'Menu']
        : ['Orders', 'Purchases', 'Reports', 'Menu management'];

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
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const ListTile(
                leading: Icon(Icons.dashboard_outlined),
                title: Text('Dashboard'),
                selected: true,
              ),
              for (final s in upcoming)
                ListTile(
                  title: Text(s),
                  subtitle: const Text('Coming soon'),
                  enabled: false,
                ),
            ],
          ),
        ),
      ),
      body: const DashboardScreen(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth.dart';
import '../dashboard/dashboard_screen.dart';

/// Role-based shell. Dashboard (M1), Orders / Reports / Z-Report (M2) and
/// Menu / Expenses management (M3) are live. Owner and manager currently get
/// the same screens — the server's `AdminOnly` policy already treats them alike.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider).valueOrNull;
    if (session == null) return const SizedBox.shrink();

    final isOwner = session.role == Role.owner;
    final title = isOwner ? 'Owner' : 'Manager';

    void open(String route) {
      Navigator.of(context).pop(); // close the drawer
      context.push(route);
    }

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
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Orders'),
                onTap: () => open('/orders'),
              ),
              ListTile(
                leading: const Icon(Icons.bar_chart_outlined),
                title: const Text('Reports'),
                onTap: () => open('/reports'),
              ),
              ListTile(
                leading: const Icon(Icons.summarize_outlined),
                title: const Text('Z-Report'),
                onTap: () => open('/z-report'),
              ),
              ListTile(
                leading: const Icon(Icons.restaurant_menu_outlined),
                title: const Text('Menu'),
                onTap: () => open('/menu'),
              ),
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Expenses'),
                onTap: () => open('/expenses'),
              ),
            ],
          ),
        ),
      ),
      body: const DashboardScreen(),
    );
  }
}

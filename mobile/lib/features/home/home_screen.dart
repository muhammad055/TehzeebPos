import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth.dart';
import '../../core/theme.dart';
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
    final roleLabel = isOwner ? 'Owner' : 'Manager';

    void open(String route) {
      Navigator.of(context).pop(); // close the drawer
      context.push(route);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            _DrawerHeader(username: session.username, roleLabel: roleLabel),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                children: [
                  const _NavItem(
                    icon: Icons.space_dashboard_rounded,
                    label: 'Dashboard',
                    selected: true,
                  ),
                  _NavItem(
                    icon: Icons.receipt_long_rounded,
                    label: 'Orders',
                    onTap: () => open('/orders'),
                  ),
                  _NavItem(
                    icon: Icons.bar_chart_rounded,
                    label: 'Reports',
                    onTap: () => open('/reports'),
                  ),
                  _NavItem(
                    icon: Icons.summarize_rounded,
                    label: 'Z-Report',
                    onTap: () => open('/z-report'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: Divider(),
                  ),
                  _NavItem(
                    icon: Icons.restaurant_menu_rounded,
                    label: 'Menu',
                    onTap: () => open('/menu'),
                  ),
                  _NavItem(
                    icon: Icons.payments_rounded,
                    label: 'Expenses',
                    onTap: () => open('/expenses'),
                  ),
                  _NavItem(
                    icon: Icons.inventory_2_rounded,
                    label: 'Inventory',
                    onTap: () => open('/inventory'),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _NavItem(
                  icon: Icons.logout_rounded,
                  label: 'Sign out',
                  onTap: () => ref.read(authProvider.notifier).logout(),
                ),
              ),
            ),
          ],
        ),
      ),
      body: const DashboardScreen(),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.username, required this.roleLabel});
  final String username;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(
                  username.isEmpty ? '?' : username[0].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 14),
              Text(username,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(roleLabel,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 4),
              Text('Tehzeeb Restaurant & Kitchen',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, this.onTap, this.selected = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        onTap: onTap,
        selected: selected,
        selectedTileColor: AppColors.accentDim,
        selectedColor: AppColors.accentDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

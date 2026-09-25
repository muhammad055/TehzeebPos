import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/expenses/expense_form_screen.dart';
import '../features/expenses/expenses_screen.dart';
import '../features/home/home_screen.dart';
import '../features/menu/dish_form_screen.dart';
import '../features/menu/menu_screen.dart';
import '../features/home/not_allowed_screen.dart';
import '../features/orders/order_detail_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/reports/zreport_screen.dart';
import 'auth.dart';

/// Role-based route guard. Signed-out → /login; cashier → /not-allowed
/// (mobile is not a POS); owner/admin → /home (which picks the mode).
final routerProvider = Provider<GoRouter>((ref) {
  // Re-evaluate redirects whenever the auth state changes.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (auth.isLoading) return null;
      final session = auth.valueOrNull;
      final loc = state.matchedLocation;

      if (session == null) return loc == '/login' ? null : '/login';
      if (session.role == Role.cashier) {
        return loc == '/not-allowed' ? null : '/not-allowed';
      }
      if (loc == '/login' || loc == '/not-allowed') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/not-allowed', builder: (_, __) => const NotAllowedScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/orders', builder: (_, __) => const OrdersScreen()),
      GoRoute(
        path: '/orders/:id',
        builder: (_, state) =>
            OrderDetailScreen(orderId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(path: '/menu', builder: (_, __) => const MenuScreen()),
      // '/menu/new' must be declared before '/menu/:id'.
      GoRoute(path: '/menu/new', builder: (_, __) => const DishFormScreen()),
      GoRoute(
        path: '/menu/:id',
        builder: (_, state) => DishFormScreen(dishId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(path: '/expenses', builder: (_, __) => const ExpensesScreen()),
      GoRoute(path: '/expenses/new', builder: (_, __) => const ExpenseFormScreen()),
      GoRoute(
        path: '/expenses/:id',
        builder: (_, state) =>
            ExpenseFormScreen(purchaseId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
      GoRoute(path: '/z-report', builder: (_, __) => const ZReportScreen()),
    ],
  );
});

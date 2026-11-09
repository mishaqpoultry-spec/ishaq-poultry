import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/parties/party.dart';
import '../features/parties/party_detail_screen.dart';
import '../features/parties/party_list_screen.dart';
import '../features/purchases/purchases_screen.dart';
import '../features/sales/rates_screen.dart';
import '../features/sales/supplies_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/stock/stock_screen.dart';
import '../widgets/common.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects whenever login state changes.
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  List<GoRoute> partyRoutes(PartyKind kind) => [
        GoRoute(
          path: kind.endpoint,
          pageBuilder: (_, _) => NoTransitionPage(child: PartyListScreen(kind: kind)),
          routes: [
            GoRoute(
              path: ':id',
              builder: (_, s) => PartyDetailScreen(kind: kind, id: int.parse(s.pathParameters['id']!)),
            ),
          ],
        ),
      ];

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (auth.isLoading) return state.matchedLocation == '/splash' ? null : '/splash';
      final loggedIn = auth.value != null;
      final atAuthPage = state.matchedLocation == '/login' || state.matchedLocation == '/splash';
      if (!loggedIn) return state.matchedLocation == '/login' ? null : '/login';
      if (atAuthPage) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const Scaffold(body: LoadingView())),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/dashboard', pageBuilder: (_, _) => const NoTransitionPage(child: DashboardScreen())),
          ...partyRoutes(PartyKind.customer),
          ...partyRoutes(PartyKind.supplier),
          GoRoute(path: '/purchases', pageBuilder: (_, _) => const NoTransitionPage(child: PurchasesScreen())),
          GoRoute(path: '/supplies', pageBuilder: (_, _) => const NoTransitionPage(child: SuppliesScreen())),
          GoRoute(path: '/rates', pageBuilder: (_, _) => const NoTransitionPage(child: RatesScreen())),
          GoRoute(path: '/stock', pageBuilder: (_, _) => const NoTransitionPage(child: StockScreen())),
        ],
      ),
    ],
  );
});

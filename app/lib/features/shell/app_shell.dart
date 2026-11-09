import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../auth/auth_controller.dart';

class NavItem {
  const NavItem(this.path, this.label, this.icon, this.selectedIcon);
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

// New modules get added here as each phase is completed.
const navItems = [
  NavItem('/dashboard', 'Dashboard', Icons.dashboard_outlined, Icons.dashboard),
  NavItem('/supplies', 'Supply / Invoices', Icons.receipt_long_outlined, Icons.receipt_long),
  NavItem('/customers', 'Customers', Icons.storefront_outlined, Icons.storefront),
  NavItem('/rates', 'Rates', Icons.sell_outlined, Icons.sell),
];

/// Sidebar on desktop/tablet, drawer on phones.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  int get _index {
    final i = navItems.indexWhere((n) => location.startsWith(n.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final user = ref.watch(currentUserProvider);

    if (width < 900) {
      return Scaffold(
        appBar: AppBar(title: const BrandTitle(compact: true)),
        drawer: Drawer(
          backgroundColor: Colors.white,
          child: SafeArea(
            child: Column(children: [
              const Padding(padding: EdgeInsets.all(20), child: BrandTitle()),
              const Divider(height: 1),
              Expanded(
                child: ListView(children: [
                  for (var i = 0; i < navItems.length; i++)
                    ListTile(
                      leading: Icon(i == _index ? navItems[i].selectedIcon : navItems[i].icon),
                      title: Text(navItems[i].label),
                      selected: i == _index,
                      selectedTileColor: AppColors.greenSoft,
                      onTap: () {
                        Navigator.pop(context);
                        context.go(navItems[i].path);
                      },
                    ),
                ]),
              ),
              const Divider(height: 1),
              _UserTile(user: user),
            ]),
          ),
        ),
        body: child,
      );
    }

    final extended = width >= 1200;
    return Scaffold(
      body: Row(children: [
        NavigationRail(
          extended: extended,
          minExtendedWidth: 230,
          selectedIndex: _index,
          onDestinationSelected: (i) => context.go(navItems[i].path),
          leading: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: extended ? const BrandTitle() : const AppLogo(size: 40),
          ),
          trailing: Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(width: extended ? 230 : 80, child: _UserTile(user: user, compact: !extended)),
            ),
          ),
          destinations: [
            for (final n in navItems)
              NavigationRailDestination(icon: Icon(n.icon), selectedIcon: Icon(n.selectedIcon), label: Text(n.label)),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: child),
      ]),
    );
  }
}

class _UserTile extends ConsumerWidget {
  const _UserTile({required this.user, this.compact = false});
  final AppUser? user;
  final bool compact;

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    if (await confirm(context, 'Logout', 'Do you want to log out?', ok: 'Logout')) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: IconButton(tooltip: 'Logout', icon: const Icon(Icons.logout), onPressed: () => _logout(context, ref)),
      );
    }
    return ListTile(
      leading: const CircleAvatar(backgroundColor: AppColors.greenSoft, child: Icon(Icons.person, color: AppColors.green)),
      title: Text(user?.fullName ?? '', overflow: TextOverflow.ellipsis),
      subtitle: Text(user?.role ?? ''),
      trailing: IconButton(tooltip: 'Logout', icon: const Icon(Icons.logout), onPressed: () => _logout(context, ref)),
    );
  }
}

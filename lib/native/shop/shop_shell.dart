import 'package:flutter/material.dart';

import '../../models/app_config.dart';
import '../native_config.dart';
import '../native_more.dart';
import '../native_ui.dart';
import '../site_page.dart';
import 'shop_api.dart';
import 'shop_cart.dart';
import 'shop_cart_screen.dart';
import 'shop_catalog.dart';
import 'shop_widgets.dart';

/// The native shop app (WooCommerce, Shopify): Shop, Categories, Cart, Account (the site's
/// account page) and More (the app's own menu items from the panel).
class ShopShell extends StatefulWidget {
  final AppConfig appConfig;
  final NativeConfig native;
  /// The platform behind the screens.
  final ShopApi api;

  const ShopShell({super.key, required this.appConfig, required this.native, required this.api});

  @override
  State<ShopShell> createState() => _ShopShellState();
}

class _ShopShellState extends State<ShopShell> {
  late final ShopScope scope;
  int tab = ShopTabs.shop;

  @override
  void initState() {
    super.initState();
    final api = widget.api;
    scope = ShopScope(
      app: widget.appConfig,
      native: widget.native,
      api: api,
      cart: ShopCartController(api),
      colors: NativeColors.of(widget.appConfig),
      openTab: (t) => setState(() => tab = t),
    );
    scope.cart.load();
    initNativePush();
  }

  @override
  Widget build(BuildContext context) {
    final t = scope.t;
    return Theme(
      data: scope.colors.theme(),
      child: Builder(builder: (context) {
        return PopScope(
          canPop: tab == ShopTabs.shop,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(() => tab = ShopTabs.shop);
          },
          child: Scaffold(
            body: IndexedStack(
              index: tab,
              children: [
                ShopHomeScreen(scope: scope),
                ShopCategoriesScreen(scope: scope),
                ShopCartScreen(scope: scope),
                _AccountTab(scope: scope),
                NativeMoreTab(app: scope.app, native: scope.native, openSite: scope.openSite),
              ],
            ),
            bottomNavigationBar: ListenableBuilder(
              listenable: scope.cart,
              builder: (context, _) => NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: (i) => setState(() => tab = i),
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                height: 64,
                destinations: [
                  NavigationDestination(icon: const Icon(Icons.storefront_outlined), selectedIcon: const Icon(Icons.storefront), label: t('shop', 'Shop')),
                  NavigationDestination(icon: const Icon(Icons.grid_view_outlined), selectedIcon: const Icon(Icons.grid_view), label: t('categories', 'Categories')),
                  NavigationDestination(
                    icon: BadgeIcon(icon: Icons.shopping_bag_outlined, count: scope.cart.count),
                    selectedIcon: BadgeIcon(icon: Icons.shopping_bag, count: scope.cart.count),
                    label: t('cart', 'Cart'),
                  ),
                  NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: t('account', 'Account')),
                  NavigationDestination(icon: const Icon(Icons.menu), label: t('more', 'More')),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _AccountTab extends StatelessWidget {
  final ShopScope scope;
  const _AccountTab({required this.scope});

  @override
  Widget build(BuildContext context) {
    final path = scope.native.settings['account_path'];
    return Scaffold(
      appBar: AppBar(title: Text(scope.t('account', 'Account'))),
      body: SitePage(
        appConfig: scope.app,
        url: scope.native.sitePage(path is String && path.isNotEmpty ? path : scope.api.accountPath),
        title: scope.t('account', 'Account'),
        embedded: true,
      ),
    );
  }
}

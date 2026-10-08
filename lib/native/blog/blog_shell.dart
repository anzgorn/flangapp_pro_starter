import 'package:flutter/material.dart';

import '../../models/app_config.dart';
import '../native_config.dart';
import '../native_more.dart';
import '../native_ui.dart';
import 'blog_screens.dart';
import 'wp_api.dart';

/// The native WordPress app: Home (latest posts), Categories, Search and More
/// (the app's own menu items from the panel + the website).
class BlogShell extends StatefulWidget {
  final AppConfig appConfig;
  final NativeConfig native;

  const BlogShell({super.key, required this.appConfig, required this.native});

  @override
  State<BlogShell> createState() => _BlogShellState();
}

class _BlogShellState extends State<BlogShell> {
  late final BlogScope scope;
  int tab = BlogTabs.home;

  @override
  void initState() {
    super.initState();
    scope = BlogScope(
      app: widget.appConfig,
      native: widget.native,
      api: WpApi(widget.native),
      colors: NativeColors.of(widget.appConfig),
    );
    initNativePush();
  }

  @override
  Widget build(BuildContext context) {
    final t = scope.t;
    return Theme(
      data: scope.colors.theme(),
      child: Builder(builder: (context) {
        return PopScope(
          canPop: tab == BlogTabs.home,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(() => tab = BlogTabs.home);
          },
          child: Scaffold(
            body: IndexedStack(
              index: tab,
              children: [
                BlogHomeScreen(scope: scope, onSearch: () => setState(() => tab = BlogTabs.search)),
                BlogCategoriesScreen(scope: scope),
                BlogSearchScreen(scope: scope),
                NativeMoreTab(app: scope.app, native: scope.native, openSite: scope.openSite),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              height: 64,
              destinations: [
                NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: t('home', 'Home')),
                NavigationDestination(icon: const Icon(Icons.grid_view_outlined), selectedIcon: const Icon(Icons.grid_view), label: t('categories', 'Categories')),
                NavigationDestination(icon: const Icon(Icons.search), label: t('search', 'Search')),
                NavigationDestination(icon: const Icon(Icons.menu), label: t('more', 'More')),
              ],
            ),
          ),
        );
      }),
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/app_config.dart';
import '../native_config.dart';
import '../native_ui.dart';
import '../site_page.dart';
import 'shop_api.dart';
import 'shop_cart.dart';
import 'shop_models.dart';
import 'shop_product.dart';

/// Bottom tab positions of the shop app.
class ShopTabs {
  static const shop = 0;
  static const categories = 1;
  static const cart = 2;
  static const account = 3;
  static const more = 4;
}

/// Everything the shop screens share.
class ShopScope {
  final AppConfig app;
  final NativeConfig native;
  final ShopApi api;
  final ShopCartController cart;
  final NativeColors colors;
  /// Switch the bottom tab (e.g. "continue shopping" from the empty cart).
  final void Function(int tab) openTab;

  ShopScope({
    required this.app,
    required this.native,
    required this.api,
    required this.cart,
    required this.colors,
    required this.openTab,
  });

  String t(String key, String fallback) => native.text(key, fallback);

  /// Open a screen over the tabs, in the app's colours (pushed routes sit above
  /// the shell, so they don't inherit its theme by themselves).
  Future<T?> push<T>(BuildContext context, Widget page) {
    return Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => Theme(data: colors.theme(), child: page)));
  }

  void openProduct(BuildContext context, ShopProduct product) {
    push(context, ShopProductScreen(scope: this, product: product));
  }

  void openSite(BuildContext context, String url, String title) {
    push(context, SitePage(appConfig: app, url: url, title: title));
  }
}

class PriceView extends StatelessWidget {
  final ShopPrices prices;
  final double size;

  const PriceView(this.prices, {super.key, this.size = 15});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final single = prices.rangeMin == null || prices.rangeMin == prices.rangeMax;
    if (prices.onSale && single) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Text(prices.display, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: accent)),
          Text(prices.regularDisplay,
              style: TextStyle(fontSize: size - 2, color: Colors.grey.shade600, decoration: TextDecoration.lineThrough)),
        ],
      );
    }
    return Text(prices.display, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700));
  }
}

class ProductCard extends StatelessWidget {
  final ShopScope scope;
  final ShopProduct product;

  const ProductCard({super.key, required this.scope, required this.product});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => scope.openProduct(context, product),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: NetImage(product.images.isNotEmpty ? product.images.first.thumbnail : ''),
                ),
                if (product.prices.onSale)
                  Positioned(left: 8, top: 8, child: _Tag(scope.t('sale', 'Sale'), Theme.of(context).colorScheme.primary)),
                if (!product.inStock)
                  Positioned(left: 8, bottom: 8, child: _Tag(scope.t('out_of_stock', 'Out of stock'), Colors.black54)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.25)),
          const SizedBox(height: 4),
          PriceView(product.prices, size: 14),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

/// Pages of products that load as the list scrolls.
class ProductPager extends ChangeNotifier {
  final Future<ShopPage> Function(String? cursor) fetch;

  final List<ShopProduct> items = [];
  String? _next;
  bool _started = false;
  bool loading = false;
  String? error;

  ProductPager(this.fetch);

  bool get done => _started && _next == null;
  bool get firstLoad => loading && items.isEmpty;

  Future<void> reload() async {
    items.clear();
    _next = null;
    _started = false;
    error = null;
    await more();
  }

  Future<void> more() async {
    if (loading || done) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await fetch(_next);
      _started = true;
      _next = page.next;
      items.addAll(page.products);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

/// A grid of products for a CustomScrollView, fed by a ProductPager.
class ProductGridSliver extends StatelessWidget {
  final ShopScope scope;
  final ProductPager pager;

  const ProductGridSliver({super.key, required this.scope, required this.pager});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pager,
      builder: (context, _) {
        if (pager.firstLoad) {
          return const SliverFillRemaining(hasScrollBody: false, child: Padding(padding: EdgeInsets.all(48), child: LoadingView()));
        }
        if (pager.items.isEmpty && pager.error != null) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorView(message: pager.error!, retryLabel: scope.t('retry', 'Try again'), onRetry: pager.reload),
          );
        }
        if (pager.items.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyView(icon: Icons.inventory_2_outlined, message: scope.t('no_products', 'No products here yet')),
          );
        }
        final width = MediaQuery.of(context).size.width;
        final columns = width >= 900 ? 4 : (width >= 600 ? 3 : 2);
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverMainAxisGroup(slivers: [
            SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 20,
                crossAxisSpacing: 14,
                childAspectRatio: 0.66,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => ProductCard(scope: scope, product: pager.items[i]),
                childCount: pager.items.length,
              ),
            ),
            if (pager.loading)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16), child: LoadingView())),
          ]),
        );
      },
    );
  }
}

/// Loads the next page when the user scrolls near the end.
bool loadMoreOnScroll(ScrollNotification n, ProductPager pager) {
  if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
    pager.more();
  }
  return false;
}

class QuantityStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final int step;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 9999,
    this.step = 1,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove, size: 18),
            onPressed: enabled && value - step >= min ? () => onChanged(value - step) : null,
          ),
          SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 18),
            onPressed: enabled && value + step <= max ? () => onChanged(value + step) : null,
          ),
        ],
      ),
    );
  }
}

/// The cart icon with its badge, for app bars.
class CartAction extends StatelessWidget {
  final ShopScope scope;

  const CartAction({super.key, required this.scope});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scope.cart,
      builder: (context, _) => IconButton(
        icon: BadgeIcon(icon: Icons.shopping_bag_outlined, count: scope.cart.count),
        onPressed: () {
          Navigator.of(context).popUntil((r) => r.isFirst);
          scope.openTab(ShopTabs.cart);
        },
      ),
    );
  }
}

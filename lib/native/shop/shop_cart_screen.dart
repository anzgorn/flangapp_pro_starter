import 'package:flutter/material.dart';

import '../native_ui.dart';
import '../site_page.dart';
import 'shop_models.dart';
import 'shop_widgets.dart';

/// Cart tab. Checkout happens on the shop's own checkout page (payments, shipping
/// and taxes stay exactly as the shop sets them up), opened inside the app.
class ShopCartScreen extends StatelessWidget {
  final ShopScope scope;
  const ShopCartScreen({super.key, required this.scope});

  void _checkout(BuildContext context) {
    final cart = scope.cart;
    final start = scope.api.checkout(cart.cart);
    if (start == null) return;
    var placed = false;
    scope.push(
      context,
      SitePage(
        appConfig: scope.app,
        url: start.url,
        title: scope.t('checkout', 'Checkout'),
        startScript: start.script,
        onUrl: (url) {
          if (!placed && scope.api.isOrderComplete(url)) {
            placed = true;
            cart.orderPlaced();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(scope.t('cart', 'Cart'))),
      body: ListenableBuilder(
        listenable: scope.cart,
        builder: (context, _) {
          final cart = scope.cart.cart;
          if (cart.items.isEmpty && scope.cart.busy) {
            return const LoadingView();
          }
          if (cart.items.isEmpty && scope.cart.error != null) {
            return ErrorView(message: scope.cart.error!, retryLabel: scope.t('retry', 'Try again'), onRetry: scope.cart.load);
          }
          if (cart.items.isEmpty) {
            return EmptyView(
              icon: Icons.shopping_bag_outlined,
              message: scope.t('cart_empty', 'Your cart is empty'),
              action: FilledButton(
                onPressed: () => scope.openTab(ShopTabs.shop),
                child: Text(scope.t('continue_shopping', 'Continue shopping')),
              ),
            );
          }
          return Column(
            children: [
              if (scope.cart.busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: scope.cart.load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, i) => _CartLine(scope: scope, item: cart.items[i]),
                  ),
                ),
              ),
              _Totals(scope: scope, cart: cart, onCheckout: () => _checkout(context)),
            ],
          );
        },
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  final ShopScope scope;
  final ShopCartItem item;
  const _CartLine({required this.scope, required this.item});

  @override
  Widget build(BuildContext context) {
    final busy = scope.cart.busy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: 72, height: 72, child: NetImage(item.image)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                if (item.variationText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(item.variationText, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ),
                const SizedBox(height: 6),
                Text(item.money.format(item.lineTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    QuantityStepper(
                      value: item.quantity,
                      max: item.maxQuantity,
                      enabled: item.editable && !busy,
                      onChanged: (q) => _update(context, q),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: Colors.grey.shade600),
                      tooltip: scope.t('remove', 'Remove'),
                      onPressed: busy ? null : () => _remove(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _update(BuildContext context, int quantity) async {
    if (!await scope.cart.setQuantity(item, quantity) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(scope.cart.error ?? '')));
    }
  }

  Future<void> _remove(BuildContext context) async {
    if (!await scope.cart.remove(item) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(scope.cart.error ?? '')));
    }
  }
}

class _Totals extends StatelessWidget {
  final ShopScope scope;
  final ShopCart cart;
  final VoidCallback onCheckout;
  const _Totals({required this.scope, required this.cart, required this.onCheckout});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cart.discount > 0) _row(scope.t('discount', 'Discount'), '-${cart.money.format(cart.discount)}', false),
              _row(scope.t('subtotal', 'Subtotal'), cart.money.format(cart.subtotal), true),
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(scope.t('checkout_note', 'Shipping and taxes are calculated at checkout'),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: scope.cart.busy ? null : onCheckout,
                  child: Text(scope.t('checkout', 'Checkout'), style: const TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, bool bold) {
    final style = TextStyle(fontSize: bold ? 17 : 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Text(label, style: style), const Spacer(), Text(value, style: style)]),
    );
  }
}

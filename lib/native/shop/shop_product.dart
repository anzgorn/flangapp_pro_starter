import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../native_ui.dart';
import 'shop_models.dart';
import 'shop_widgets.dart';

class ShopProductScreen extends StatefulWidget {
  final ShopScope scope;
  /// From a list: shown at once, then refreshed with the full product.
  final ShopProduct product;

  const ShopProductScreen({super.key, required this.scope, required this.product});

  @override
  State<ShopProductScreen> createState() => _ShopProductScreenState();
}

class _ShopProductScreenState extends State<ShopProductScreen> {
  late ShopProduct product = widget.product;
  /// The full product (with its options) has arrived.
  bool loaded = false;
  final Map<String, String> selection = {};
  /// The chosen variation as a product: its own price, stock and quantity rules.
  ShopProduct? chosen;
  int quantity = 1;
  int image = 0;
  bool adding = false;

  ShopScope get scope => widget.scope;

  @override
  void initState() {
    super.initState();
    scope.api.product(product.id).then((full) {
      if (mounted) {
        setState(() {
          product = full;
          loaded = true;
          _fitQuantity();
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => loaded = true);
    });
  }

  ShopVariation? get variation {
    if (!product.hasOptions) return null;
    for (final v in product.variations) {
      if (v.matches(selection)) return v;
    }
    return null;
  }

  /// Can [term] of [attribute] still be bought with the other options chosen so
  /// far? Only answered where the platform tells stock per variant (Shopify).
  bool _available(ShopAttribute attribute, String term) {
    for (final v in product.variations) {
      final value = v.attributes[attribute.name];
      if (value != null && value.isNotEmpty && value != term) continue;
      var fits = true;
      for (final s in selection.entries) {
        if (s.key == attribute.name) continue;
        final other = v.attributes[s.key];
        if (other != null && other.isNotEmpty && other != s.value) {
          fits = false;
          break;
        }
      }
      if (fits && v.inStock != false) return true;
    }
    return false;
  }

  bool get optionsChosen => !product.hasOptions || product.attributes.every((a) => selection.containsKey(a.name));

  void _select(ShopAttribute attribute, String term, bool on) {
    setState(() {
      if (on) {
        selection[attribute.name] = term;
      } else {
        selection.remove(attribute.name);
      }
      chosen = null;
    });
    final v = optionsChosen ? variation : null;
    if (v != null) {
      scope.api.variation(product, v).then((p) {
        if (mounted && p != null && variation?.id == v.id) {
          setState(() {
            chosen = p;
            _fitQuantity();
          });
        }
      }).catchError((_) {});
    }
  }

  /// The product (or chosen variation) whose price and quantity rules apply.
  ShopProduct get buying => chosen ?? product;

  /// Keep the quantity inside the shop's rules (e.g. "at least 2").
  void _fitQuantity() {
    final p = buying;
    if (quantity < p.minQty) quantity = p.minQty;
    if (quantity > p.maxQty) quantity = p.maxQty;
  }

  bool get inStock => buying.inStock;

  /// What goes into the cart: the chosen variation, or the product itself.
  String? get _buyId => product.hasOptions ? variation?.id : (product.buyId.isNotEmpty ? product.buyId : null);

  Future<void> _add() async {
    if (!optionsChosen) {
      _toast(scope.t('choose_options', 'Choose the options first'));
      return;
    }
    final id = _buyId;
    if (id == null) {
      _toast(scope.t('unavailable', 'This combination is not available'));
      return;
    }
    setState(() => adding = true);
    final ok = await scope.cart.add(id, quantity, {
      for (final a in product.attributes)
        if (selection[a.name] != null) a.key: selection[a.name]!
    });
    if (!mounted) return;
    setState(() => adding = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(scope.t('added', 'Added to cart')),
        action: SnackBarAction(
          label: scope.t('view_cart', 'View cart'),
          onPressed: () {
            Navigator.of(context).popUntil((r) => r.isFirst);
            scope.openTab(ShopTabs.cart);
          },
        ),
      ));
    } else {
      _toast(scope.cart.error ?? scope.t('error', 'Something went wrong'));
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final images = product.images;
    return Scaffold(
      appBar: AppBar(
        title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [CartAction(scope: scope)],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: images.isEmpty
                ? const NetImage('')
                : Stack(
                    children: [
                      PageView.builder(
                        itemCount: images.length,
                        onPageChanged: (i) => setState(() => image = i),
                        itemBuilder: (_, i) => NetImage(images[i].src, fit: BoxFit.contain),
                      ),
                      if (images.length > 1)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < images.length; i++)
                                Container(
                                  width: i == image ? 18 : 7,
                                  height: 7,
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  decoration: BoxDecoration(
                                    color: i == image ? Theme.of(context).colorScheme.primary : Colors.black26,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3)),
                const SizedBox(height: 8),
                PriceView(buying.prices, size: 20),
                if (!inStock) ...[
                  const SizedBox(height: 6),
                  Text(scope.t('out_of_stock', 'Out of stock'), style: TextStyle(color: Colors.red.shade700)),
                ],
                if (product.shortDescription.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _html(product.shortDescription),
                ],
                for (final attribute in product.attributes) ...[
                  const SizedBox(height: 16),
                  Text(attribute.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final term in attribute.terms.entries)
                        ChoiceChip(
                          label: Text(term.value),
                          selected: selection[attribute.name] == term.key,
                          onSelected: _available(attribute, term.key) || selection[attribute.name] == term.key
                              ? (on) => _select(attribute, term.key, on)
                              : null,
                        ),
                    ],
                  ),
                ],
                if (product.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text(scope.t('description', 'Description'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _html(product.description),
                ],
              ],
            ),
          ),
        ],
      ),
      // Buying stays in reach however long the options and description are.
      bottomNavigationBar: Material(
        elevation: 8,
        color: Colors.white,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: product.buyableInApp
                ? Row(
                    children: [
                      QuantityStepper(
                        value: quantity,
                        min: buying.minQty,
                        max: buying.maxQty,
                        step: buying.stepQty,
                        enabled: inStock,
                        onChanged: (q) => setState(() => quantity = q),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: loaded && inStock && product.purchasable && !adding ? _add : null,
                            icon: adding || !loaded
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.add_shopping_cart),
                            label: Text(scope.t('add_to_cart', 'Add to cart')),
                          ),
                        ),
                      ),
                    ],
                  )
                : SizedBox(
                    height: 48,
                    child: FilledButton.tonalIcon(
                      onPressed: () => scope.openSite(context, product.url, product.name),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(product.siteButtonText.isNotEmpty ? product.siteButtonText : scope.t('view_on_site', 'View on the site')),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _html(String html) {
    return HtmlWidget(
      html,
      textStyle: TextStyle(fontSize: 15, height: 1.45, color: Colors.grey.shade800),
      onTapUrl: (url) {
        scope.openSite(context, url, product.name);
        return true;
      },
    );
  }
}

import '../native_config.dart';
import 'shop_models.dart';

class ShopException implements Exception {
  final String message;
  ShopException(this.message);

  @override
  String toString() => message;
}

enum ShopSort { popular, newest, priceLow, priceHigh, relevance }

/// One page of products + where the next one starts (null = the last page).
class ShopPage {
  final List<ShopProduct> products;
  final String? next;
  const ShopPage(this.products, this.next);
}

/// How checkout starts on the site: the page to open, and an optional script to
/// run on it once (older WooCommerce fills the site's cart that way).
class CheckoutStart {
  final String url;
  final String? script;
  const CheckoutStart(this.url, [this.script]);
}

/// A shop platform behind the native shop screens.
abstract class ShopApi {
  NativeConfig get config;

  /// The customer account page on the site.
  String get accountPath;

  Future<List<ShopCategory>> categories();

  /// [cursor] = the previous page's `next`, null for the first page.
  Future<ShopPage> products({String? cursor, String? category, String search = '', ShopSort sort = ShopSort.popular});

  Future<ShopProduct> product(String id);

  /// The chosen variation as a product (its own price, stock and quantity rules),
  /// or null when the platform has nothing more than the variation itself.
  Future<ShopProduct?> variation(ShopProduct product, ShopVariation variation);

  /// Pick up the cart kept from the last session.
  Future<void> restoreCart();

  /// Start over with an empty cart (after an order was placed).
  Future<void> forgetCart();

  Future<ShopCart> cart();

  /// [options] = attribute key → chosen value (WooCommerce variations need them).
  Future<ShopCart> addItem(String id, int quantity, Map<String, String> options);

  Future<ShopCart> updateItem(ShopCartItem item, int quantity);

  Future<ShopCart> removeItem(ShopCartItem item);

  /// Where checkout of this cart starts, or null when it can't start.
  CheckoutStart? checkout(ShopCart cart);

  /// The checkout reached its "thank you" page.
  bool isOrderComplete(String url);
}

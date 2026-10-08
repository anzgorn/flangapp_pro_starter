import 'package:flutter/foundation.dart';

import 'shop_api.dart';
import 'shop_models.dart';

/// The app's cart, shared by every screen (badge, product page, cart screen).
class ShopCartController extends ChangeNotifier {
  final ShopApi api;

  ShopCart cart = const ShopCart();
  bool busy = false;
  String? error;

  ShopCartController(this.api);

  int get count => cart.itemsCount;

  Future<void> load() async {
    await api.restoreCart();
    await _run(() async => cart = await api.cart());
  }

  Future<bool> add(String id, int quantity, [Map<String, String> options = const {}]) {
    return _run(() async => cart = await api.addItem(id, quantity, options));
  }

  Future<bool> setQuantity(ShopCartItem item, int quantity) {
    if (quantity <= 0) return remove(item);
    return _run(() async => cart = await api.updateItem(item, quantity));
  }

  Future<bool> remove(ShopCartItem item) {
    return _run(() async => cart = await api.removeItem(item));
  }

  /// The order was placed on the site: the app starts a fresh cart.
  Future<void> orderPlaced() async {
    await api.forgetCart();
    cart = const ShopCart();
    notifyListeners();
    await _run(() async => cart = await api.cart());
  }

  Future<bool> _run(Future<void> Function() action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

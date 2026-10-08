import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../native_config.dart';
import '../shop/shop_api.dart';
import '../shop/shop_models.dart';

/// WooCommerce Store API (public, no keys). The cart lives on the shop's server
/// and is identified by the Cart-Token the API hands out; the token is kept on the
/// device so the cart survives restarts. Older WooCommerce without cart tokens
/// works with the Nonce header + the session cookie instead.
class WooApi implements ShopApi {
  @override
  final NativeConfig config;
  final Dio _dio;
  String? _cartToken;
  String? _nonce;
  String? _cookie;

  WooApi(this.config)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: {'Accept': 'application/json'},
          validateStatus: (_) => true,
        ));

  @override
  String get accountPath => '/my-account/';

  String get _tokenKey => 'woo_cart_token_${config.siteUrl}';

  // ------------------------------------------------------------------
  // HTTP
  // ------------------------------------------------------------------

  /// A Store API route on the WordPress REST root (pretty or ?rest_route= permalinks).
  String _url(String route, [Map<String, dynamic>? query]) {
    final base = config.apiBase;
    final params = query == null || query.isEmpty
        ? ''
        : query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent('${e.value}')}').join('&');
    if (base.contains('rest_route=')) {
      final url = base.replaceFirst(RegExp(r'rest_route=[^&]*'), 'rest_route=/wc/store/v1/$route');
      return params.isEmpty ? url : '$url&$params';
    }
    final url = '${base.replaceFirst(RegExp(r'/+$'), '')}/wc/store/v1/$route';
    return params.isEmpty ? url : '$url?$params';
  }

  Future<Response> _get(String route, [Map<String, dynamic>? query]) async {
    return _check(await _dio.get(_url(route, query), options: Options(headers: _cartHeaders())));
  }

  Future<Response> _post(String route, Map<String, dynamic> body) async {
    return _check(await _dio.post(_url(route), data: body, options: Options(headers: _cartHeaders(), contentType: 'application/json')));
  }

  Map<String, String> _cartHeaders() {
    return {
      if (_cartToken != null && _cartToken!.isNotEmpty) 'Cart-Token': _cartToken!,
      if (_nonce != null && _nonce!.isNotEmpty) 'Nonce': _nonce!,
      // Cookie sessions only matter without cart tokens (older WooCommerce, not on web).
      if (!kIsWeb && (_cartToken == null || _cartToken!.isEmpty) && _cookie != null) 'Cookie': _cookie!,
    };
  }

  Response _check(Response res) {
    final token = res.headers.value('cart-token');
    if (token != null && token.isNotEmpty && token != _cartToken) {
      _cartToken = token;
      SharedPreferences.getInstance().then((p) => p.setString(_tokenKey, token));
    }
    final nonce = res.headers.value('nonce');
    if (nonce != null && nonce.isNotEmpty) {
      _nonce = nonce;
    }
    final cookies = res.headers['set-cookie'];
    if (cookies != null && cookies.isNotEmpty) {
      _cookie = cookies.map((c) => c.split(';').first).join('; ');
    }
    final status = res.statusCode ?? 0;
    if (status >= 400 || status == 0) {
      final data = res.data;
      final message = data is Map && data['message'] != null ? decodeText(data['message']) : 'The shop did not answer (HTTP $status).';
      throw ShopException(message);
    }
    return res;
  }

  // ------------------------------------------------------------------
  // CATALOG
  // ------------------------------------------------------------------

  @override
  Future<List<ShopCategory>> categories() async {
    final res = await _get('products/categories');
    final list = res.data is List ? res.data as List : [];
    return [
      for (final c in list)
        if (c is Map)
          ShopCategory(
            id: '${c['id']}',
            name: decodeText(c['name']),
            count: toInt(c['count']),
            parent: toInt(c['parent']) == 0 ? '' : '${c['parent']}',
            image: c['image'] is Map ? _image(c['image']) : null,
          )
    ];
  }

  @override
  Future<ShopPage> products({String? cursor, String? category, String search = '', ShopSort sort = ShopSort.popular}) async {
    final page = toInt(cursor, 1);
    final order = switch (sort) {
      ShopSort.popular => ['popularity', 'desc'],
      ShopSort.newest => ['date', 'desc'],
      ShopSort.priceLow => ['price', 'asc'],
      ShopSort.priceHigh => ['price', 'desc'],
      ShopSort.relevance => <String>[],
    };
    final res = await _get('products', {
      'page': page,
      'per_page': 20,
      if (order.isNotEmpty) 'orderby': order[0],
      if (order.isNotEmpty) 'order': order[1],
      if (category != null) 'category': category,
      if (search.isNotEmpty) 'search': search,
    });
    final list = res.data is List ? res.data as List : [];
    final pages = int.tryParse(res.headers.value('x-wp-totalpages') ?? '') ?? 1;
    return ShopPage([for (final p in list) if (p is Map) _product(p)], page < pages ? '${page + 1}' : null);
  }

  @override
  Future<ShopProduct> product(String id) async {
    final res = await _get('products/$id');
    if (res.data is! Map) throw ShopException('Product not found.');
    return _product(res.data as Map);
  }

  @override
  Future<ShopProduct?> variation(ShopProduct product, ShopVariation variation) => this.product(variation.id);

  // ------------------------------------------------------------------
  // CART
  // ------------------------------------------------------------------

  @override
  Future<void> restoreCart() async {
    final prefs = await SharedPreferences.getInstance();
    _cartToken = prefs.getString(_tokenKey);
  }

  @override
  Future<void> forgetCart() async {
    _cartToken = null;
    _cookie = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  @override
  Future<ShopCart> cart() async => _cart(await _get('cart'));

  @override
  Future<ShopCart> addItem(String id, int quantity, Map<String, String> options) async {
    return _cart(await _post('cart/add-item', {
      'id': toInt(id),
      'quantity': quantity,
      if (options.isNotEmpty) 'variation': [for (final o in options.entries) {'attribute': o.key, 'value': o.value}],
    }));
  }

  @override
  Future<ShopCart> updateItem(ShopCartItem item, int quantity) async =>
      _cart(await _post('cart/update-item', {'key': item.key, 'quantity': quantity}));

  @override
  Future<ShopCart> removeItem(ShopCartItem item) async => _cart(await _post('cart/remove-item', {'key': item.key}));

  /// WooCommerce 10+: one Shareable Checkout URL fills the site's cart and opens
  /// checkout. Older shops: open a light page of the shop, put the items into the
  /// site's own cart from there (the page's session), then go to checkout.
  @override
  CheckoutStart? checkout(ShopCart cart) {
    if (cart.items.isEmpty) return null;
    if (config.checkout == 'checkout_link') {
      final products = cart.items.map((i) => '${i.itemId}:${i.quantity}').join(',');
      final coupon = cart.coupons.isNotEmpty ? '&coupon=${Uri.encodeQueryComponent(cart.coupons.first)}' : '';
      return CheckoutStart(config.sitePage('/checkout-link/?products=$products$coupon'));
    }
    final lines = cart.items.map((i) => '[${i.itemId},${i.quantity}]').join(',');
    final checkoutUrl = config.sitePage('/checkout/');
    final script = '''
(async function(){
  if (window.__flangappCartSent) return; window.__flangappCartSent = true;
  var items = [$lines];
  for (var i = 0; i < items.length; i++) {
    var body = new URLSearchParams(); body.append('product_id', items[i][0]); body.append('quantity', items[i][1]);
    try { await fetch('/?wc-ajax=add_to_cart', {method: 'POST', body: body, credentials: 'include'}); } catch (e) {}
  }
  window.location.href = ${_jsString(checkoutUrl)};
})();
''';
    final start = '${config.apiBase}${config.apiBase.contains('?') ? '&' : '?'}_fields=name';
    return CheckoutStart(start, script);
  }

  @override
  bool isOrderComplete(String url) => url.contains('order-received');

  // ------------------------------------------------------------------
  // PARSING
  // ------------------------------------------------------------------

  ShopMoney _money(Map json) {
    return ShopMoney(
      minorUnit: toInt(json['currency_minor_unit'], 2),
      prefix: decodeText(json['currency_prefix']),
      suffix: decodeText(json['currency_suffix']),
      decimalSeparator: (json['currency_decimal_separator'] ?? '.').toString(),
      thousandSeparator: (json['currency_thousand_separator'] ?? ',').toString(),
      code: (json['currency_code'] ?? '').toString(),
    );
  }

  ShopImage _image(Map json) {
    final src = (json['src'] ?? '').toString();
    final thumb = (json['thumbnail'] ?? '').toString();
    return ShopImage(src, thumb.isNotEmpty ? thumb : src);
  }

  ShopProduct _product(Map json) {
    final prices = json['prices'] is Map ? json['prices'] as Map : {};
    final range = prices['price_range'];
    final addToCart = json['add_to_cart'] is Map ? json['add_to_cart'] as Map : {};
    final type = (json['type'] ?? 'simple').toString();
    final sale = toInt(prices['sale_price']);
    final regular = toInt(prices['regular_price']);
    final variations = [
      for (final v in (json['variations'] as List? ?? []))
        if (v is Map)
          ShopVariation(id: '${v['id']}', attributes: {
            for (final a in (v['attributes'] as List? ?? []))
              if (a is Map) decodeText(a['name']): (a['value'] ?? '').toString()
          })
    ];
    final attributes = [
      for (final a in (json['attributes'] as List? ?? []))
        if (a is Map && a['has_variations'] == true)
          ShopAttribute(
            name: decodeText(a['name']),
            key: (a['taxonomy'] ?? '').toString().isNotEmpty ? a['taxonomy'].toString() : decodeText(a['name']),
            terms: {
              for (final t in (a['terms'] as List? ?? []))
                if (t is Map) (t['slug'] ?? t['name']).toString(): decodeText(t['name'])
            },
          )
    ];
    final variable = type == 'variable' && variations.isNotEmpty;
    return ShopProduct(
      id: '${json['id']}',
      name: decodeText(json['name']),
      url: (json['permalink'] ?? '').toString(),
      shortDescription: (json['short_description'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      prices: ShopPrices(
        money: _money(prices),
        price: toInt(prices['price']),
        regularPrice: sale > 0 && sale < regular ? regular : 0,
        rangeMin: range is Map ? toInt(range['min_amount']) : null,
        rangeMax: range is Map ? toInt(range['max_amount']) : null,
      ),
      images: [for (final i in (json['images'] as List? ?? [])) if (i is Map) _image(i)],
      inStock: json['is_in_stock'] != false,
      purchasable: json['is_purchasable'] != false,
      buyableInApp: type == 'simple' || variable,
      buyId: '${json['id']}',
      siteButtonText: decodeText(addToCart['text']),
      attributes: variable ? attributes : const [],
      variations: variable ? variations : const [],
      minQty: toInt(addToCart['minimum'], 1).clamp(1, 9999),
      maxQty: toInt(addToCart['maximum'], 9999).clamp(1, 9999),
      stepQty: toInt(addToCart['multiple_of'], 1).clamp(1, 9999),
    );
  }

  ShopCart _cart(Response res) {
    if (res.data is! Map) return const ShopCart();
    final json = res.data as Map;
    final totals = json['totals'] is Map ? json['totals'] as Map : {};
    return ShopCart(
      items: [
        for (final i in (json['items'] as List? ?? []))
          if (i is Map) _cartItem(i)
      ],
      itemsCount: toInt(json['items_count']),
      subtotal: toInt(totals['total_items']),
      discount: toInt(totals['total_discount']),
      coupons: [for (final c in (json['coupons'] as List? ?? [])) if (c is Map) (c['code'] ?? '').toString()],
      money: _money(totals),
    );
  }

  ShopCartItem _cartItem(Map json) {
    final images = json['images'] as List? ?? [];
    final limits = json['quantity_limits'] is Map ? json['quantity_limits'] as Map : {};
    final totals = json['totals'] is Map ? json['totals'] as Map : {};
    return ShopCartItem(
      key: (json['key'] ?? '').toString(),
      itemId: '${json['id']}',
      name: decodeText(json['name']),
      quantity: toInt(json['quantity'], 1),
      maxQuantity: toInt(limits['maximum'], 9999),
      editable: limits['editable'] != false,
      image: images.isNotEmpty && images.first is Map ? _image(images.first).thumbnail : '',
      variationText: [
        for (final v in (json['variation'] as List? ?? []))
          if (v is Map) '${decodeText(v['attribute'])}: ${decodeText(v['value'])}'
      ].join(', '),
      lineTotal: toInt(totals['line_subtotal']),
      money: _money(totals),
    );
  }

  static String _jsString(String value) => "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
}

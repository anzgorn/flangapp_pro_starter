import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../native_config.dart';
import '../shop/shop_api.dart';
import '../shop/shop_models.dart';

/// Shopify Storefront API (GraphQL). Works without a token (catalog, search,
/// cart); the owner's public Storefront token, when set, is sent along. The cart
/// is a Storefront cart whose id is kept on the device; checkout opens the
/// cart's own `checkoutUrl` (Shopify checkout) inside the app.
class ShopifyApi implements ShopApi {
  @override
  final NativeConfig config;
  final Dio _dio;
  String? _cartId;

  ShopifyApi(this.config)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: {
            'Accept': 'application/json',
            if (config.storefrontToken.isNotEmpty) 'X-Shopify-Storefront-Access-Token': config.storefrontToken,
          },
          validateStatus: (_) => true,
        ));

  @override
  String get accountPath => '/account';

  String get _cartKey => 'shopify_cart_id_${config.shopDomain}';

  static const _pageSize = 20;

  // ------------------------------------------------------------------
  // GRAPHQL
  // ------------------------------------------------------------------

  static const _card = '''
fragment Card on Product {
  id title handle onlineStoreUrl availableForSale
  featuredImage { url(transform: {maxWidth: 600}) }
  priceRange { minVariantPrice { amount currencyCode } maxVariantPrice { amount currencyCode } }
  compareAtPriceRange { minVariantPrice { amount } }
}''';

  static const _cartFields = '''
fragment CartFields on Cart {
  id checkoutUrl totalQuantity
  cost { subtotalAmount { amount currencyCode } totalAmount { amount currencyCode } }
  discountCodes { code applicable }
  lines(first: 100) { nodes {
    id quantity
    cost { totalAmount { amount currencyCode } }
    merchandise { ... on ProductVariant {
      id title
      product { title }
      image { url(transform: {maxWidth: 200}) }
      selectedOptions { name value }
    } }
  } }
}''';

  Future<Map<String, dynamic>> _query(String query, [Map<String, dynamic> variables = const {}]) async {
    final res = await _dio.post(config.apiBase, data: {'query': query, 'variables': variables}, options: Options(contentType: 'application/json'));
    final status = res.statusCode ?? 0;
    final body = res.data;
    if (status == 401 || status == 403) {
      throw ShopException('The store refused the request (HTTP $status).');
    }
    if (body is! Map) {
      throw ShopException('The store did not answer (HTTP $status).');
    }
    final errors = body['errors'];
    if (errors is List && errors.isNotEmpty && body['data'] == null) {
      throw ShopException(decodeText(errors.first is Map ? errors.first['message'] : errors.first));
    }
    return Map<String, dynamic>.from(body['data'] as Map? ?? {});
  }

  /// Mutation result: the cart, or the first user error as an exception.
  ShopCart _mutationCart(Map<String, dynamic> data, String field) {
    final payload = data[field];
    if (payload is! Map) throw ShopException('The store did not answer.');
    final errors = payload['userErrors'];
    if (errors is List && errors.isNotEmpty) {
      throw ShopException(decodeText(errors.first['message']));
    }
    final cart = payload['cart'];
    if (cart is Map) _remember(cart['id'].toString());
    return cart is Map ? _cart(cart) : const ShopCart();
  }

  // ------------------------------------------------------------------
  // CATALOG
  // ------------------------------------------------------------------

  @override
  Future<List<ShopCategory>> categories() async {
    final data = await _query('''
{ collections(first: 100, sortKey: TITLE) { nodes { id title image { url(transform: {maxWidth: 200}) } } } }''');
    final nodes = (data['collections']?['nodes'] as List?) ?? [];
    return [
      for (final c in nodes)
        if (c is Map)
          ShopCategory(
            id: c['id'].toString(),
            name: decodeText(c['title']),
            image: c['image'] is Map ? ShopImage(c['image']['url'].toString()) : null,
          )
    ];
  }

  @override
  Future<ShopPage> products({String? cursor, String? category, String search = '', ShopSort sort = ShopSort.popular}) async {
    final reverse = sort == ShopSort.newest || sort == ShopSort.priceHigh;
    Map<String, dynamic>? connection;
    if (category != null) {
      final key = switch (sort) {
        ShopSort.popular => 'BEST_SELLING',
        ShopSort.newest => 'CREATED',
        ShopSort.priceLow || ShopSort.priceHigh => 'PRICE',
        ShopSort.relevance => 'COLLECTION_DEFAULT',
      };
      final data = await _query('''
query(\$id: ID!, \$after: String) { collection(id: \$id) {
  products(first: $_pageSize, after: \$after, sortKey: $key, reverse: $reverse) { nodes { ...Card } pageInfo { hasNextPage endCursor } }
} }
$_card''', {'id': category, 'after': cursor});
      connection = (data['collection'] as Map?)?['products'] as Map<String, dynamic>?;
    } else {
      final key = search.isNotEmpty && sort == ShopSort.relevance
          ? 'RELEVANCE'
          : switch (sort) {
              ShopSort.popular => 'BEST_SELLING',
              ShopSort.newest => 'CREATED_AT',
              ShopSort.priceLow || ShopSort.priceHigh => 'PRICE',
              ShopSort.relevance => 'BEST_SELLING',
            };
      final data = await _query('''
query(\$after: String, \$q: String) {
  products(first: $_pageSize, after: \$after, sortKey: $key, reverse: $reverse, query: \$q) { nodes { ...Card } pageInfo { hasNextPage endCursor } }
}
$_card''', {'after': cursor, 'q': search.isEmpty ? null : search});
      connection = data['products'] as Map<String, dynamic>?;
    }
    final nodes = (connection?['nodes'] as List?) ?? [];
    final info = connection?['pageInfo'] as Map?;
    return ShopPage(
      [for (final p in nodes) if (p is Map) _product(p)],
      info != null && info['hasNextPage'] == true ? info['endCursor']?.toString() : null,
    );
  }

  @override
  Future<ShopProduct> product(String id) async {
    final data = await _query('''
query(\$id: ID!) { product(id: \$id) {
  ...Card descriptionHtml
  images(first: 10) { nodes { url(transform: {maxWidth: 1200}) } }
  options { name optionValues { name } }
  variants(first: 100) { nodes {
    id availableForSale
    price { amount currencyCode } compareAtPrice { amount }
    selectedOptions { name value }
    image { url(transform: {maxWidth: 1200}) }
  } }
} }
$_card''', {'id': id});
    final json = data['product'];
    if (json is! Map) throw ShopException('Product not found.');
    return _product(json, full: true);
  }

  /// Variants arrive with the product (price, stock): no extra request.
  @override
  Future<ShopProduct?> variation(ShopProduct product, ShopVariation variation) async {
    return ShopProduct(
      id: variation.id,
      name: product.name,
      url: product.url,
      prices: variation.prices ?? product.prices,
      inStock: variation.inStock ?? product.inStock,
      buyId: variation.id,
    );
  }

  // ------------------------------------------------------------------
  // CART
  // ------------------------------------------------------------------

  @override
  Future<void> restoreCart() async {
    final prefs = await SharedPreferences.getInstance();
    _cartId = prefs.getString(_cartKey);
  }

  void _remember(String id) {
    if (id == _cartId) return;
    _cartId = id;
    SharedPreferences.getInstance().then((p) => p.setString(_cartKey, id));
  }

  @override
  Future<void> forgetCart() async {
    _cartId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cartKey);
  }

  @override
  Future<ShopCart> cart() async {
    if (_cartId == null) return const ShopCart();
    final data = await _query('query(\$id: ID!) { cart(id: \$id) { ...CartFields } }\n$_cartFields', {'id': _cartId});
    final cart = data['cart'];
    if (cart is! Map) {
      // Expired or already checked out: start a new one on the next add.
      await forgetCart();
      return const ShopCart();
    }
    return _cart(cart);
  }

  @override
  Future<ShopCart> addItem(String id, int quantity, Map<String, String> options) async {
    final lines = [
      {'merchandiseId': id, 'quantity': quantity}
    ];
    if (_cartId == null) {
      final data = await _query('''
mutation(\$lines: [CartLineInput!]) { cartCreate(input: {lines: \$lines}) { cart { ...CartFields } userErrors { message } } }
$_cartFields''', {'lines': lines});
      return _mutationCart(data, 'cartCreate');
    }
    final data = await _query('''
mutation(\$id: ID!, \$lines: [CartLineInput!]!) { cartLinesAdd(cartId: \$id, lines: \$lines) { cart { ...CartFields } userErrors { message } } }
$_cartFields''', {'id': _cartId, 'lines': lines});
    return _mutationCart(data, 'cartLinesAdd');
  }

  @override
  Future<ShopCart> updateItem(ShopCartItem item, int quantity) async {
    final data = await _query('''
mutation(\$id: ID!, \$lines: [CartLineUpdateInput!]!) { cartLinesUpdate(cartId: \$id, lines: \$lines) { cart { ...CartFields } userErrors { message } } }
$_cartFields''', {
      'id': _cartId,
      'lines': [
        {'id': item.key, 'quantity': quantity}
      ]
    });
    return _mutationCart(data, 'cartLinesUpdate');
  }

  @override
  Future<ShopCart> removeItem(ShopCartItem item) async {
    final data = await _query('''
mutation(\$id: ID!, \$lines: [ID!]!) { cartLinesRemove(cartId: \$id, lineIds: \$lines) { cart { ...CartFields } userErrors { message } } }
$_cartFields''', {
      'id': _cartId,
      'lines': [item.key]
    });
    return _mutationCart(data, 'cartLinesRemove');
  }

  @override
  CheckoutStart? checkout(ShopCart cart) => cart.items.isEmpty || cart.checkoutUrl.isEmpty ? null : CheckoutStart(cart.checkoutUrl);

  @override
  bool isOrderComplete(String url) => url.contains('/thank_you') || url.contains('/thank-you') || RegExp(r'/orders/[^/?]+').hasMatch(url);

  // ------------------------------------------------------------------
  // PARSING
  // ------------------------------------------------------------------

  ShopProduct _product(Map json, {bool full = false}) {
    final min = json['priceRange']?['minVariantPrice'] as Map?;
    final max = json['priceRange']?['maxVariantPrice'] as Map?;
    final money = _money(min?['currencyCode']?.toString() ?? config.currency);
    final compareAt = _amount(json['compareAtPriceRange']?['minVariantPrice']?['amount'], money);
    final price = _amount(min?['amount'], money);
    final url = (json['onlineStoreUrl'] ?? '').toString();

    var images = <ShopImage>[];
    final attributes = <ShopAttribute>[];
    final variations = <ShopVariation>[];
    var buyId = '';
    if (full) {
      images = [
        for (final i in ((json['images']?['nodes'] as List?) ?? []))
          if (i is Map) ShopImage(i['url'].toString())
      ];
      final variants = (json['variants']?['nodes'] as List?) ?? [];
      for (final v in variants) {
        if (v is! Map) continue;
        final vPrice = v['price'] is Map ? v['price'] as Map : {};
        variations.add(ShopVariation(
          id: v['id'].toString(),
          attributes: {
            for (final o in (v['selectedOptions'] as List? ?? []))
              if (o is Map) decodeText(o['name']): decodeText(o['value'])
          },
          prices: ShopPrices(
            money: money,
            price: _amount(vPrice['amount'], money),
            regularPrice: _amount(v['compareAtPrice']?['amount'], money),
          ),
          inStock: v['availableForSale'] == true,
          image: v['image'] is Map ? ShopImage(v['image']['url'].toString()) : null,
        ));
      }
      // A product with one "Default Title" variant has no real options.
      final hasOptions = variants.length > 1;
      if (hasOptions) {
        for (final o in (json['options'] as List? ?? [])) {
          if (o is! Map) continue;
          final values = [for (final v in (o['optionValues'] as List? ?? [])) if (v is Map) decodeText(v['name'])];
          if (values.isEmpty) continue;
          attributes.add(ShopAttribute(
            name: decodeText(o['name']),
            key: decodeText(o['name']),
            terms: {for (final v in values) v: v},
          ));
        }
      } else if (variations.isNotEmpty) {
        buyId = variations.first.id;
      }
    }
    final featured = json['featuredImage'];
    if (images.isEmpty && featured is Map) {
      images = [ShopImage(featured['url'].toString())];
    }

    return ShopProduct(
      id: json['id'].toString(),
      name: decodeText(json['title']),
      url: url.isNotEmpty ? url : config.sitePage('/products/${json['handle']}'),
      description: (json['descriptionHtml'] ?? '').toString(),
      prices: ShopPrices(
        money: money,
        price: price,
        regularPrice: compareAt > price ? compareAt : 0,
        rangeMin: price,
        rangeMax: _amount(max?['amount'], money),
      ),
      images: images,
      inStock: json['availableForSale'] != false,
      // From a list we don't know the variants yet; the product page loads them.
      buyableInApp: true,
      buyId: buyId,
      attributes: attributes.isNotEmpty ? attributes : const [],
      variations: attributes.isNotEmpty ? variations : const [],
    );
  }

  ShopCart _cart(Map json) {
    final lines = (json['lines']?['nodes'] as List?) ?? [];
    final subtotal = json['cost']?['subtotalAmount'] as Map?;
    final money = _money(subtotal?['currencyCode']?.toString() ?? config.currency);
    return ShopCart(
      items: [
        for (final l in lines)
          if (l is Map && l['merchandise'] is Map) _line(l)
      ],
      itemsCount: toInt(json['totalQuantity']),
      subtotal: _amount(subtotal?['amount'], money),
      coupons: [
        for (final d in (json['discountCodes'] as List? ?? []))
          if (d is Map && d['applicable'] == true) d['code'].toString()
      ],
      money: money,
      checkoutUrl: (json['checkoutUrl'] ?? '').toString(),
    );
  }

  ShopCartItem _line(Map json) {
    final m = json['merchandise'] as Map;
    final total = json['cost']?['totalAmount'] as Map?;
    final money = _money(total?['currencyCode']?.toString() ?? config.currency);
    final options = [
      for (final o in (m['selectedOptions'] as List? ?? []))
        if (o is Map && !(o['name'] == 'Title' && o['value'] == 'Default Title')) '${decodeText(o['name'])}: ${decodeText(o['value'])}'
    ];
    return ShopCartItem(
      key: json['id'].toString(),
      itemId: m['id'].toString(),
      name: decodeText(m['product']?['title'] ?? m['title']),
      quantity: toInt(json['quantity'], 1),
      image: m['image'] is Map ? m['image']['url'].toString() : '',
      variationText: options.join(', '),
      lineTotal: _amount(total?['amount'], money),
      money: money,
    );
  }

  // Currencies without cents, and with three decimals.
  static const _noMinor = {'JPY', 'KRW', 'VND', 'CLP', 'ISK', 'UGX', 'XAF', 'XOF', 'PYG', 'RWF'};
  static const _threeMinor = {'KWD', 'BHD', 'JOD', 'OMR', 'TND', 'IQD', 'LYD'};
  static const _prefix = {
    'USD': r'$', 'CAD': r'CA$', 'AUD': r'A$', 'NZD': r'NZ$', 'HKD': r'HK$', 'SGD': r'S$', 'MXN': r'MX$',
    'BRL': r'R$', 'EUR': '€', 'GBP': '£', 'JPY': '¥', 'CNY': '¥', 'INR': '₹', 'ILS': '₪', 'TRY': '₺',
    'KRW': '₩', 'AED': 'AED ', 'CHF': 'CHF ', 'ZAR': 'R',
  };
  static const _suffix = {
    'RUB': ' ₽', 'UAH': ' ₴', 'KZT': ' ₸', 'SEK': ' kr', 'NOK': ' kr', 'DKK': ' kr', 'PLN': ' zł', 'CZK': ' Kč',
  };

  ShopMoney _money(String code) {
    final c = code.toUpperCase();
    final suffix = _suffix[c];
    return ShopMoney(
      minorUnit: _noMinor.contains(c) ? 0 : (_threeMinor.contains(c) ? 3 : 2),
      prefix: suffix != null ? '' : (_prefix[c] ?? (c.isEmpty ? '' : '$c ')),
      suffix: suffix ?? '',
      code: c,
    );
  }

  /// "28.5" → 2850 (minor units of the currency).
  int _amount(dynamic value, ShopMoney money) {
    final text = (value ?? '').toString();
    if (text.isEmpty) return 0;
    final parts = text.split('.');
    final whole = int.tryParse(parts[0]) ?? 0;
    var fraction = parts.length > 1 ? parts[1] : '';
    fraction = (fraction + '0' * money.minorUnit).substring(0, money.minorUnit);
    var result = whole;
    for (var i = 0; i < money.minorUnit; i++) {
      result *= 10;
    }
    return result + (int.tryParse(fraction.isEmpty ? '0' : fraction) ?? 0);
  }
}

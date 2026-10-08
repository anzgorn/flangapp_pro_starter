// Platform-neutral shop data. Each platform adapter (WooCommerce Store API,
// Shopify Storefront API) turns its own answers into these, so the native shop
// screens are the same for every platform. Money is kept in minor units.

const _named = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ',
  'ndash': '–', 'mdash': '—', 'hellip': '…', 'laquo': '«', 'raquo': '»',
  'lsquo': '‘', 'rsquo': '’', 'ldquo': '“', 'rdquo': '”', 'trade': '™',
  'reg': '®', 'copy': '©', 'deg': '°', 'times': '×', 'euro': '€', 'pound': '£',
};

/// Plain text from API strings that may be HTML-escaped ("Turkey 12 &#8211; 14lb")
/// or carry tags.
String decodeText(dynamic value) {
  final text = (value ?? '').toString().replaceAll(RegExp(r'<[^>]*>'), '');
  return text.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
    final code = m[1]!;
    if (code.startsWith('#x') || code.startsWith('#X')) {
      final n = int.tryParse(code.substring(2), radix: 16);
      return n != null ? String.fromCharCode(n) : m[0]!;
    }
    if (code.startsWith('#')) {
      final n = int.tryParse(code.substring(1));
      return n != null ? String.fromCharCode(n) : m[0]!;
    }
    return _named[code] ?? m[0]!;
  }).trim();
}

int toInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  return int.tryParse((value ?? '').toString()) ?? fallback;
}

/// How a shop writes money: minor units + symbol and separators.
class ShopMoney {
  final int minorUnit;
  final String prefix;
  final String suffix;
  final String decimalSeparator;
  final String thousandSeparator;
  final String code;

  const ShopMoney({
    this.minorUnit = 2,
    this.prefix = '',
    this.suffix = '',
    this.decimalSeparator = '.',
    this.thousandSeparator = ',',
    this.code = '',
  });

  /// 1999 (minor units) → "$19.99"
  String format(int amount) {
    final negative = amount < 0;
    final digits = amount.abs().toString().padLeft(minorUnit + 1, '0');
    final whole = minorUnit > 0 ? digits.substring(0, digits.length - minorUnit) : digits;
    final fraction = minorUnit > 0 ? digits.substring(digits.length - minorUnit) : '';
    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(thousandSeparator);
      grouped.write(whole[i]);
    }
    final number = fraction.isEmpty ? grouped.toString() : '$grouped$decimalSeparator$fraction';
    return '${negative ? '-' : ''}$prefix$number$suffix';
  }
}

class ShopPrices {
  final ShopMoney money;
  final int price;
  /// Price before a sale (0 = no sale).
  final int regularPrice;
  /// A variable product's range (null = one price).
  final int? rangeMin;
  final int? rangeMax;

  const ShopPrices({required this.money, required this.price, this.regularPrice = 0, this.rangeMin, this.rangeMax});

  bool get onSale => regularPrice > price && price > 0;

  String get display {
    if (rangeMin != null && rangeMax != null && rangeMin != rangeMax) {
      return '${money.format(rangeMin!)} – ${money.format(rangeMax!)}';
    }
    return money.format(price);
  }

  String get regularDisplay => money.format(regularPrice);
}

class ShopImage {
  final String src;
  final String thumbnail;
  const ShopImage(this.src, [String? thumbnail]) : thumbnail = thumbnail ?? src;
}

class ShopCategory {
  final String id;
  final String name;
  /// Number of products, when the platform tells (Shopify doesn't).
  final int? count;
  /// Parent category id, "" for a top-level one.
  final String parent;
  final ShopImage? image;

  const ShopCategory({required this.id, required this.name, this.count, this.parent = '', this.image});
}

/// One choosable option of a product with variants, e.g. Size: S / M / L.
class ShopAttribute {
  final String name;
  /// What the platform wants back when adding to cart (WooCommerce taxonomy, e.g. "pa_size").
  final String key;
  /// value → label
  final Map<String, String> terms;

  const ShopAttribute({required this.name, required this.key, required this.terms});
}

class ShopVariation {
  final String id;
  /// attribute name → value ("" = any value)
  final Map<String, String> attributes;
  /// Known up front on Shopify; on WooCommerce loaded when chosen.
  final ShopPrices? prices;
  final bool? inStock;
  final ShopImage? image;

  const ShopVariation({required this.id, required this.attributes, this.prices, this.inStock, this.image});

  bool matches(Map<String, String> selection) {
    for (final entry in attributes.entries) {
      final chosen = selection[entry.key];
      if (chosen == null) return false;
      if (entry.value.isNotEmpty && entry.value != chosen) return false;
    }
    return true;
  }
}

class ShopProduct {
  final String id;
  final String name;
  /// The page of the product on the site.
  final String url;
  final String shortDescription;
  final String description;
  final ShopPrices prices;
  final List<ShopImage> images;
  final bool inStock;
  final bool purchasable;
  /// Can be bought in the app (simple or with variants); otherwise "view on the site".
  final bool buyableInApp;
  /// What goes into the cart for a product without options (Shopify: its only variant).
  final String buyId;
  final String siteButtonText;
  final List<ShopAttribute> attributes;
  final List<ShopVariation> variations;
  final int minQty;
  final int maxQty;
  final int stepQty;

  const ShopProduct({
    required this.id,
    required this.name,
    required this.url,
    this.shortDescription = '',
    this.description = '',
    required this.prices,
    this.images = const [],
    this.inStock = true,
    this.purchasable = true,
    this.buyableInApp = true,
    required this.buyId,
    this.siteButtonText = '',
    this.attributes = const [],
    this.variations = const [],
    this.minQty = 1,
    this.maxQty = 9999,
    this.stepQty = 1,
  });

  bool get hasOptions => attributes.isNotEmpty && variations.isNotEmpty;
}

class ShopCartItem {
  /// The line in the cart (WooCommerce item key, Shopify line id).
  final String key;
  /// What was bought (product / variation / Shopify variant id).
  final String itemId;
  final String name;
  final int quantity;
  final int maxQuantity;
  final bool editable;
  final String image;
  final String variationText;
  final int lineTotal;
  final ShopMoney money;

  const ShopCartItem({
    required this.key,
    required this.itemId,
    required this.name,
    required this.quantity,
    this.maxQuantity = 9999,
    this.editable = true,
    this.image = '',
    this.variationText = '',
    required this.lineTotal,
    required this.money,
  });
}

class ShopCart {
  final List<ShopCartItem> items;
  final int itemsCount;
  final int subtotal;
  final int discount;
  final List<String> coupons;
  final ShopMoney money;
  /// Shopify: the cart's own checkout page.
  final String checkoutUrl;

  const ShopCart({
    this.items = const [],
    this.itemsCount = 0,
    this.subtotal = 0,
    this.discount = 0,
    this.coupons = const [],
    this.money = const ShopMoney(),
    this.checkoutUrl = '',
  });
}

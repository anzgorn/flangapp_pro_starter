/// The native-app part of the bridge config (`native` in public/bridge/app),
/// present when the app runs as a native CMS app instead of the website.
class NativeConfig {
  /// woocommerce | shopify | wordpress
  final String cms;
  /// The store's website, e.g. https://shop.example.com (no trailing slash).
  final String siteUrl;
  /// WordPress REST root (https://shop.example.com/wp-json/) or the Shopify
  /// Storefront GraphQL endpoint.
  final String apiBase;
  final String shopDomain;
  final String apiVersion;
  final String storefrontToken;
  /// How the cart reaches the site's checkout: checkout_link | add_to_cart | shopify
  final String checkout;
  final String currency;
  /// Native screen settings (set by the panel / Flangapp AI); may be empty.
  final Map<String, dynamic> settings;

  NativeConfig({
    required this.cms,
    required this.siteUrl,
    required this.apiBase,
    required this.shopDomain,
    required this.apiVersion,
    required this.storefrontToken,
    required this.checkout,
    required this.currency,
    required this.settings,
  });

  static NativeConfig? fromJson(dynamic json) {
    if (json is! Map) {
      return null;
    }
    final settings = json['config'];
    return NativeConfig(
      cms: (json['cms'] ?? '').toString(),
      siteUrl: (json['site_url'] ?? '').toString().replaceFirst(RegExp(r'/+$'), ''),
      apiBase: (json['api_base'] ?? '').toString(),
      shopDomain: (json['shop_domain'] ?? '').toString(),
      apiVersion: (json['api_version'] ?? '').toString(),
      storefrontToken: (json['storefront_token'] ?? '').toString(),
      checkout: (json['checkout'] ?? '').toString(),
      currency: (json['currency'] ?? '').toString(),
      settings: settings is Map ? Map<String, dynamic>.from(settings) : <String, dynamic>{},
    );
  }

  /// A UI text: the configured translation, or the English default.
  String text(String key, String fallback) {
    final strings = settings['strings'];
    if (strings is Map && strings[key] is String && (strings[key] as String).isNotEmpty) {
      return strings[key] as String;
    }
    return fallback;
  }

  /// An absolute address on the store's site for a path like "/my-account/".
  String sitePage(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return siteUrl + (path.startsWith('/') ? path : '/$path');
  }
}

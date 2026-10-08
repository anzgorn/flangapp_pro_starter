import 'package:flutter/material.dart';

import '../models/app_config.dart';
import '../views/web_viewer.dart';
import 'blog/blog_shell.dart';
import 'shop/shop_shell.dart';
import 'shopify/shopify_api.dart';
import 'woo/woo_api.dart';

/// The first screen after the splash: native screens for a native CMS app,
/// the website otherwise — and the website whenever the native part can't run
/// (a platform this build doesn't have yet, or an incomplete connection).
Widget appHome(AppConfig config) {
  final native = config.native;
  if (native != null && native.siteUrl.isNotEmpty && native.apiBase.isNotEmpty) {
    switch (config.appKind) {
      case 'woocommerce':
        return ShopShell(appConfig: config, native: native, api: WooApi(native));
      case 'shopify':
        if (native.shopDomain.isNotEmpty) {
          return ShopShell(appConfig: config, native: native, api: ShopifyApi(native));
        }
      case 'wordpress':
        return BlogShell(appConfig: config, native: native);
    }
  }
  return WebViewer(appConfig: config);
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ionicons_named/ionicons_named.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/config.dart';
import '../models/app_config.dart';
import '../models/enum/action_type.dart';
import '../models/navigation_item.dart';
import 'native_config.dart';

/// Opens a site page inside the native app (each shell pushes it in its theme).
typedef OpenSite = void Function(BuildContext context, String url, String title);

/// Push notifications, as in the website app.
void initNativePush() {
  if (!kIsWeb && Config.oneSignalPushId.isNotEmpty) {
    OneSignal.initialize(Config.oneSignalPushId);
    OneSignal.Notifications.requestPermission(true);
  }
}

/// A "main" navigation item from the panel: a site page, an external link, mail, call or share.
Future<void> openNavigationItem(BuildContext context, AppConfig app, NativeConfig native, NavigationItem item, OpenSite openSite) async {
  switch (item.type) {
    case ActionType.internal:
      openSite(context, item.value, item.name);
      break;
    case ActionType.external:
      final uri = Uri.parse(item.value);
      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      break;
    case ActionType.email:
      await launchUrl(Uri(scheme: 'mailto', path: item.value));
      break;
    case ActionType.phone:
      await launchUrl(Uri(scheme: 'tel', path: item.value));
      break;
    case ActionType.share:
      Share.share('${app.appName} ${native.siteUrl}');
      break;
  }
}

/// More tab of every native app: the panel's "main" navigation items + the website.
class NativeMoreTab extends StatelessWidget {
  final AppConfig app;
  final NativeConfig native;
  final OpenSite openSite;

  const NativeMoreTab({super.key, required this.app, required this.native, required this.openSite});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(native.text('more', 'More'))),
      body: ListView(
        children: [
          for (final item in app.mainNavigation)
            ListTile(
              leading: Icon(ionicons[item.icon] ?? Icons.link),
              title: Text(item.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openNavigationItem(context, app, native, item, openSite),
            ),
          ListTile(
            leading: const Icon(Icons.public),
            title: Text(native.text('open_site', 'Open the website')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openSite(context, native.siteUrl, app.appName),
          ),
        ],
      ),
    );
  }
}

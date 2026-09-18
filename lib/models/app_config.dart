import 'package:flangapp_pro/models/enum/action_type.dart';

import 'enum/background_mode.dart';
import 'enum/load_indicator.dart';
import 'enum/template.dart';
import 'navigation_item.dart';

class AppConfig {
  // Main
  final String appName;
  final String appLink;
  final bool displayTitle;
  final String color;
  final String activeColor;
  final String iconColor;
  final bool isDark;
  final bool pullToRefreshEnabled;
  final String customUserAgent;
  final String email;
  final Template template;
  final LoadIndicator indicator;
  final String indicatorColor;
  // Access
  final bool cameraEnabled;
  final bool microphoneEnabled;
  final bool gpsEnabled;
  // Drawer
  final String drawerTitle;
  final String drawerSubtitle;
  final BackgroundMode drawerBackgroundMode;
  final String drawerBackgroundColor;
  final bool drawerIsDark;
  final String drawerBackgroundImage;
  final String drawerLogoImage;
  final bool drawerIsDisplayLogo;
  // Styles for hide
  final List<dynamic> cssHideBlock;
  // Localization
  final String messageErrorBrowser;
  final String errorBrowserImage;
  final String titleExit;
  final String messageExit;
  final String actionYesDownload;
  final String actionNoDownload;
  final String contactBtn ;
  final String backBtn;
  // Navigation
  final List<NavigationItem> mainNavigation;
  final List<NavigationItem> barNavigation;
  // Custom code injected into the wrapped website (set by the AI configurator)
  final String customCss;
  final String customJs;

  AppConfig({
    required this.appName,
    required this.appLink,
    required this.displayTitle,
    required this.color,
    required this.activeColor,
    required this.iconColor,
    required this.isDark,
    required this.pullToRefreshEnabled,
    required this.customUserAgent,
    required this.email,
    required this.template,
    required this.indicator,
    required this.indicatorColor,
    required this.cameraEnabled,
    required this.microphoneEnabled,
    required this.gpsEnabled,
    required this.drawerTitle,
    required this.drawerSubtitle,
    required this.drawerBackgroundMode,
    required this.drawerBackgroundColor,
    required this.drawerIsDark,
    required this.drawerBackgroundImage,
    required this.drawerLogoImage,
    required this.drawerIsDisplayLogo,
    required this.cssHideBlock,
    required this.messageErrorBrowser,
    required this.errorBrowserImage,
    required this.titleExit,
    required this.messageExit,
    required this.actionYesDownload,
    required this.actionNoDownload,
    required this.contactBtn,
    required this.backBtn,
    required this.mainNavigation,
    required this.barNavigation,
    this.customCss = "",
    this.customJs = ""
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    List<dynamic> navigationItemsJson = json['navigation']['main'];
    List<NavigationItem> mainNavigation = navigationItemsJson.map((itemJson) {
      return NavigationItem(
        name: itemJson['name'],
        icon: itemJson['icon'],
        type: _convertToActionType(itemJson['type']),
        value: itemJson['value'],
      );
    }).toList();
    List<dynamic> navigationItemsJsonBar = json['navigation']['bar'];
    List<NavigationItem> barNavigation = navigationItemsJsonBar.map((itemJson) {
      return NavigationItem(
        name: itemJson['name'],
        icon: itemJson['icon'],
        type: _convertToActionType(itemJson['type']),
        value: itemJson['value'],
      );
    }).toList();
    return AppConfig(
      appName: json['name'],
      appLink: json['link'],
      displayTitle: json['is_display_title'],
      color: json['color'],
      activeColor: json['active_color'],
      iconColor: json['icon_color'],
      isDark: json['is_dark'],
      pullToRefreshEnabled: json['pull_to_refresh'],
      customUserAgent: json['user_agent'],
      email: json['email'],
      template: _convertToTemplate(json['template']),
      indicator: _convertToIndicator(json['indicator']),
      indicatorColor: json['indicator_color'],
      cameraEnabled: json['access']['camera'],
      microphoneEnabled: json['access']['microphone'],
      gpsEnabled: json['access']['gps'],
      drawerTitle: json['drawer']['title'],
      drawerSubtitle: json['drawer']['subtitle'],
      drawerBackgroundMode: _convertToDrawerBackgroundMode(json['drawer']['background_mode']),
      drawerIsDark: json['drawer']['is_dark'],
      drawerBackgroundImage: json['drawer']['background_image'],
      drawerLogoImage: json['drawer']['logo_image'],
      drawerBackgroundColor: json['drawer']['background_color'],
      drawerIsDisplayLogo: json['drawer']['is_display_logo'],
      cssHideBlock: json['hide_styles'],
      errorBrowserImage: json['localization']['error_image'],
      messageErrorBrowser: json['localization']['error_browser'],
      messageExit: json['localization']['exit_message'],
      titleExit: json['localization']['exit_title'],
      actionYesDownload: json['localization']['yes'],
      actionNoDownload: json['localization']['no'],
      contactBtn: json['localization']['contact'],
      backBtn: json['localization']['back'],
      mainNavigation: mainNavigation,
      barNavigation: barNavigation,
      customCss: json['custom_css'] ?? "",
      customJs: json['custom_js'] ?? "",
    );
  }

  static Template _convertToTemplate(int value) {
    switch (value) {
      case 0:
        return Template.drawer;
      case 1:
        return Template.tabs;
      case 2:
        return Template.bar;
      case 3:
        return Template.blank;
      default:
        throw Exception('Unknown template value: $value');
    }
  }

  static LoadIndicator _convertToIndicator(int value) {
    switch (value) {
      case 0:
        return LoadIndicator.none;
      case 1:
        return LoadIndicator.line;
      case 2:
        return LoadIndicator.spinner;
      default:
        throw Exception('Unknown indicator value: $value');
    }
  }

  static BackgroundMode _convertToDrawerBackgroundMode(int value) {
    switch (value) {
      case 0:
        return BackgroundMode.none;
      case 1:
        return BackgroundMode.color;
      case 2:
        return BackgroundMode.image;
      default:
        throw Exception('Unknown background mode value: $value');
    }
  }

  static ActionType _convertToActionType(int value) {
    switch (value) {
      case 0:
        return ActionType.internal;
      case 1:
        return ActionType.external;
      case 2:
        return ActionType.share;
      case 3:
        return ActionType.email;
      case 4:
        return ActionType.phone;
      default:
        throw Exception('Unknown action type value: $value');
    }
  }
}
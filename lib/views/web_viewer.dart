import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flangapp_pro/models/app_config.dart';
import 'package:flangapp_pro/services/hex_color.dart';
import 'package:flangapp_pro/widgets/app_drawer.dart';
import 'package:flangapp_pro/widgets/app_tabs.dart';
import 'package:flangapp_pro/widgets/error_page.dart';
import 'package:flangapp_pro/widgets/navbar.dart';
import 'package:flangapp_pro/widgets/offline_page.dart';
import 'package:flangapp_pro/widgets/progress_load.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/config.dart';
import '../models/enum/action_type.dart';
import '../models/enum/load_indicator.dart';
import '../models/enum/template.dart';
import '../models/navigation_item.dart';
import '../models/web_view_collection.dart';

class WebViewer extends StatefulWidget {
  final AppConfig appConfig;

  const WebViewer({super.key, required this.appConfig});

  @override
  State<WebViewer> createState() => _WebViewerState();
}

class _WebViewerState extends State<WebViewer> {

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  InAppWebViewSettings settings = InAppWebViewSettings(
    mediaPlaybackRequiresUserGesture: true,
    allowsInlineMediaPlayback: true,
    iframeAllow: "camera; microphone",
    iframeAllowFullscreen: true,
    horizontalScrollBarEnabled: false,
    geolocationEnabled: true,
    allowFileAccessFromFileURLs: true,
    useOnDownloadStart: true,
  );

  List<WebViewCollection> collection = [];
  int activePage = 0;
  bool isOffline = false;
  StreamSubscription<ConnectivityResult>? subscription;

  final urlController = TextEditingController();

  @override
  void initState() {
    createCollection();
    createPullToRefresh();
    if (Config.oneSignalPushId.isNotEmpty) {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      OneSignal.initialize(Config.oneSignalPushId);
      OneSignal.Notifications.requestPermission(true);
    }

    super.initState();

    subscription = Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      if (result == ConnectivityResult.none) {
        setState(() {
          isOffline = true;
        });
      } else {
        setState(() {
          isOffline = false;
        });
      }
    });
  }

  @override
  dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        debugPrint("didPop1: $didPop");
        if (didPop) {
          return;
        }
        if (collection[activePage].isCanBack) {
          collection[activePage].controller?.goBack();
          return;
        }
        String? res = await showDialog<String>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(widget.appConfig.titleExit),
            content: Text(widget.appConfig.messageExit),
            backgroundColor: Colors.white,
            surfaceTintColor: HexColor.fromHex(widget.appConfig.color),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, 'YES'),
                child: Text(widget.appConfig.actionYesDownload, style: const TextStyle(
                  color: Colors.blueGrey
                )),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'NO'),
                child: Text(widget.appConfig.actionNoDownload, style: TextStyle(
                  color: HexColor.fromHex(widget.appConfig.color)
                ),),
              ),
            ],
          ),
        );
        if (res == 'NO') {
          return;
        }
        SystemChannels.platform.invokeMethod('SystemNavigator.pop');
      },
      child: Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: true,
        appBar: widget.appConfig.template != Template.blank ? Navbar(
          background: widget.appConfig.color,
          isDark: widget.appConfig.isDark,
          title: widget.appConfig.displayTitle ? collection[activePage].title : widget.appConfig.appName,
          isCanBack: collection[activePage].isCanBack,
          isDrawer: widget.appConfig.template == Template.drawer,
          actions: widget.appConfig.barNavigation,
          onBack: () => collection[activePage].controller?.goBack(),
          onAction: (NavigationItem item) => navigationAction(item),
          onOpenDrawer: () => _scaffoldKey.currentState!.openDrawer(),
        ) : null,
        body: SafeArea(
          top: widget.appConfig.template == Template.blank,
          child: !isOffline ? IndexedStack(
            index: activePage,
            children: [
              for (var i = 0; i < collection.length; i ++)
                webContainer(i),
            ],
          ) : OfflinePage(),
        ),
        drawer: widget.appConfig.template == Template.drawer ? AppDrawer(
          title: widget.appConfig.drawerTitle,
          subtitle: widget.appConfig.drawerSubtitle,
          backgroundMode: widget.appConfig.drawerBackgroundMode,
          backgroundColor: widget.appConfig.drawerBackgroundColor,
          isDark: widget.appConfig.drawerIsDark,
          backgroundImage: widget.appConfig.drawerBackgroundImage,
          logoImage: widget.appConfig.drawerLogoImage,
          isDisplayLogo: widget.appConfig.drawerIsDisplayLogo,
          actions: widget.appConfig.mainNavigation,
          iconColor: widget.appConfig.iconColor,
          onAction: (NavigationItem item) => navigationAction(item),
        ) : null,
        drawerEdgeDragWidth: 0,
        bottomNavigationBar: widget.appConfig.template == Template.tabs ? AppTabs(
          actions: widget.appConfig.mainNavigation,
          activeTab: activePage,
          onChange: (index) {
            setState(() {
              activePage = index;
            });
          },
          color: widget.appConfig.activeColor,
        ) : null,
      ),
    );
  }

  Widget webContainer(int index) {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(collection[index].url)),
          initialSettings: settings,
          pullToRefreshController: widget.appConfig.pullToRefreshEnabled
              ? collection[index].pullToRefreshController
              : null,
          onWebViewCreated: (controller) {
            collection[index].controller = controller;
          },
          onProgressChanged: (controller, progress) {
            injectCss(index);
            if (progress == 100) {
              collection[index].pullToRefreshController?.endRefreshing();
            }
            setState(() {
              collection[index].progress = progress / 100;
            });
            controller.getTitle().then((value) {
              if (value != null) {
                setState(() {
                  collection[index].title = value;
                });
              }
            });
          },
          onLoadStop: (controller, url) async {
            collection[index].pullToRefreshController?.endRefreshing();
            injectJs(index);
            setState(() {
              collection[index].progress = 1;
            });
            controller.canGoBack().then((value) {
              setState(() {
                collection[index].isCanBack = value;
              });
            });
          },
          onUpdateVisitedHistory: (controller, url, androidIsReload) {
            debugPrint("UPDATE HISTORY");
            controller.canGoBack().then((value) {
              debugPrint("NEW VALUE $value");
              setState(() {
                collection[index].isCanBack = value;
              });
            });
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
              final shouldPerformDownload =
                  navigationAction.shouldPerformDownload ?? false;
              final url = navigationAction.request.url;
              if (shouldPerformDownload && url != null) {
                return NavigationActionPolicy.DOWNLOAD;
              }
            }
            var uri = navigationAction.request.url!;

            if (![
              "http",
              "https",
              "file",
              "chrome",
              "data",
              "javascript",
              "about"
            ].contains(uri.scheme)) {
              if (await canLaunchUrl(uri)) {
                // Launch the App
                await launchUrl(
                  uri,
                );
                // and cancel the request
                return NavigationActionPolicy.CANCEL;
              }
            }
            return NavigationActionPolicy.ALLOW;
          },
          onGeolocationPermissionsShowPrompt: (InAppWebViewController controller, String origin) async {
            if (widget.appConfig.gpsEnabled) {
              await Permission.location.request();
              return GeolocationPermissionShowPromptResponse(
                  origin: origin,
                  allow: true,
                  retain: true
              );
            }
          },
          onPermissionRequest: (controller, request) async {
            for (var i = 0; i < request.resources.length; i ++) {
              if (request.resources[i].toString().contains("MICROPHONE")) {
                if (widget.appConfig.microphoneEnabled) {
                  await Permission.microphone.request();
                }
              }
              if (request.resources[i].toString().contains("CAMERA")) {
                if (widget.appConfig.cameraEnabled) {
                  await Permission.camera.request();
                }
              }
            }
            return PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.GRANT);
          },
          onDownloadStartRequest: (controller, downloadStartRequest) async {
            launchUrl(Uri.parse(downloadStartRequest.url.toString()), mode: LaunchMode.externalApplication);
          },
          onReceivedHttpError: (controller, request, errorResponse) async {
            collection[index].pullToRefreshController?.endRefreshing();
            var isForMainFrame = request.isForMainFrame ?? false;
            if (!isForMainFrame) {
              return;
            }
            final snackBar = SnackBar(
              content: Text(
                  'HTTP: ${request.url}: ${errorResponse.statusCode} ${errorResponse.reasonPhrase ?? ''}'),
            );
            ScaffoldMessenger.of(context).showSnackBar(snackBar);
          },
          onReceivedError: (controller, request, error) async {
            collection[index].pullToRefreshController?.endRefreshing();
            var isForMainFrame = request.isForMainFrame ?? false;
            if (!isForMainFrame ||
                (!kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.iOS &&
                    error.type == WebResourceErrorType.CANCELLED)) {
              return;
            }
            setState(() {
              collection[index].isError = true;
            });
          }
        ),
        if (collection[index].progress < 1 && widget.appConfig.indicator != LoadIndicator.none)
          ProgressLoad(
              value: collection[index].progress,
              color: widget.appConfig.indicatorColor,
              type: widget.appConfig.indicator
          ),
        if (collection[index].isError)
          ErrorPage(
              onBack: () {
                setState(() {
                  collection[activePage].controller?.goBack();
                  collection[index].isError = false;
                });
              },
              color: widget.appConfig.color,
              email: widget.appConfig.email,
              image: widget.appConfig.errorBrowserImage,
              message: widget.appConfig.messageErrorBrowser,
              buttonBackLabel: widget.appConfig.backBtn,
              buttonContactLabel: widget.appConfig.contactBtn
          )
      ],
    );
  }

  void createCollection() {
    if (widget.appConfig.template == Template.tabs && widget.appConfig.mainNavigation.length > 1) {
      List<NavigationItem> items = widget.appConfig.mainNavigation;
      collection = [
        for (var i = 0; i < items.length; i ++)
          if (items[i].type == ActionType.internal)
            WebViewCollection(
              url: items[i].value.toString(),
              isLoading: true,
              title: widget.appConfig.appName,
              isCanBack: false,
              progress: 0,
              isError: false
            )
      ];
    } else {
      collection = [
        WebViewCollection(
          url: widget.appConfig.appLink,
          isLoading: true,
          title: widget.appConfig.appName,
          isCanBack: false,
          progress: 0,
          isError: false
        )
      ];
    }
  }

  void createPullToRefresh() {
    if (widget.appConfig.template != Template.tabs) {
      collection[0].pullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(
          color: Colors.grey,
        ),
        onRefresh: () async {
          if (defaultTargetPlatform == TargetPlatform.android) {
            collection[0].controller?.reload();
          } else if (defaultTargetPlatform == TargetPlatform.iOS) {
            collection[0].controller?.loadUrl(
                urlRequest:
                URLRequest(url: await collection[0].controller?.getUrl()));
          }
        },
      );
      return;
    }
    List<NavigationItem> items = widget.appConfig.mainNavigation;
    for (var i = 0; i < items.length; i ++) {
      if (items[i].type == ActionType.internal) {
        collection[i].pullToRefreshController = PullToRefreshController(
          settings: PullToRefreshSettings(
            color: Colors.grey,
          ),
          onRefresh: () async {
            if (defaultTargetPlatform == TargetPlatform.android) {
              collection[i].controller?.reload();
            } else if (defaultTargetPlatform == TargetPlatform.iOS) {
              collection[i].controller?.loadUrl(
                  urlRequest:
                  URLRequest(url: await collection[i].controller?.getUrl()));
            }
          },
        );
      }
    }
  }

  void injectCss(index) {
    String styles = "";
    for (var item in widget.appConfig.cssHideBlock) {
      styles = "$styles$item{ display: none; }";
    }
    // Custom CSS set by the AI configurator (restyle the wrapped site).
    if (widget.appConfig.customCss.isNotEmpty) {
      styles = "$styles\n${widget.appConfig.customCss}";
    }
    collection[index].controller?.injectCSSCode(
        source: styles
    );
  }

  // Custom JS set by the AI configurator, run after each page finishes loading.
  // Wrapped in try/catch so a bad script can't break the page.
  void injectJs(index) {
    if (widget.appConfig.customJs.isEmpty) {
      return;
    }
    collection[index].controller?.evaluateJavascript(
        source: "try { ${widget.appConfig.customJs} } catch (e) { console.error('custom js error', e); }"
    );
  }

  void navigationAction(NavigationItem item) async {
    if (item.type == ActionType.internal) {
      collection[activePage].controller?.loadUrl(
          urlRequest: URLRequest(url: WebUri(item.value))
      );
    } else if (item.type == ActionType.external) {
      WebUri uri = WebUri(item.value);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } else if (item.type == ActionType.email) {
      final Uri emailLaunchUri = Uri(
        scheme: 'mailto',
        path: item.value,
      );
      if (await canLaunchUrl(emailLaunchUri)) {
        await launchUrl(emailLaunchUri);
      }
    } else if (item.type == ActionType.phone) {
      final Uri phoneLaunchUri = Uri(
        scheme: 'tel',
        path: item.value,
      );
      if (await canLaunchUrl(phoneLaunchUri)) {
        await launchUrl(phoneLaunchUri);
      }
    } else if (item.type == ActionType.share) {
      collection[activePage].controller?.getUrl().then((url) {
        Share.share(
          "${url.toString()} ${widget.appConfig.displayTitle
              ? collection[activePage].title
              : widget.appConfig.appName}"
        );
      });
    }
  }


}
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_config.dart';

/// A page of the store's website inside the native app: checkout, the customer
/// account, and any page the native screens don't cover. It gets the same hidden
/// elements and custom CSS / JS as the website app.
class SitePage extends StatefulWidget {
  final AppConfig appConfig;
  final String url;
  final String title;
  /// Run once, after the first page has loaded (e.g. fill the site's cart).
  final String? startScript;
  /// Called with every address the page reaches (e.g. to notice "order received").
  final void Function(String url)? onUrl;
  /// Shown inside a tab: no close button.
  final bool embedded;

  const SitePage({
    super.key,
    required this.appConfig,
    required this.url,
    required this.title,
    this.startScript,
    this.onUrl,
    this.embedded = false,
  });

  @override
  State<SitePage> createState() => _SitePageState();
}

class _SitePageState extends State<SitePage> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _canBack = false;
  bool _started = false;
  String _title = '';

  final _settings = InAppWebViewSettings(
    mediaPlaybackRequiresUserGesture: true,
    allowsInlineMediaPlayback: true,
    horizontalScrollBarEnabled: false,
    geolocationEnabled: true,
    useOnDownloadStart: true,
  );

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    if (widget.appConfig.customUserAgent.isNotEmpty) {
      _settings.userAgent = widget.appConfig.customUserAgent;
    }
  }

  void _injectCss() {
    var styles = '';
    for (final item in widget.appConfig.cssHideBlock) {
      styles = '$styles$item{ display: none; }';
    }
    if (widget.appConfig.customCss.isNotEmpty) {
      styles = '$styles\n${widget.appConfig.customCss}';
    }
    if (styles.isNotEmpty) {
      _controller?.injectCSSCode(source: styles);
    }
  }

  void _injectJs() {
    if (widget.appConfig.customJs.isNotEmpty) {
      _controller?.evaluateJavascript(
          source: "try { ${widget.appConfig.customJs} } catch (e) { console.error('custom js error', e); }");
    }
  }

  Future<bool> _goBack() async {
    if (_controller != null && await _controller!.canGoBack()) {
      _controller!.goBack();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final body = Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.url)),
          initialSettings: _settings,
          onWebViewCreated: (c) => _controller = c,
          onProgressChanged: (c, p) {
            _injectCss();
            setState(() => _progress = p / 100);
          },
          onLoadStop: (c, url) async {
            _injectJs();
            if (!_started && widget.startScript != null) {
              _started = true;
              await c.evaluateJavascript(source: widget.startScript!);
            }
            final title = await c.getTitle();
            final canBack = await c.canGoBack();
            if (mounted) {
              setState(() {
                _progress = 1;
                _canBack = canBack;
                if (title != null && title.isNotEmpty && !widget.embedded) _title = title;
              });
            }
          },
          onUpdateVisitedHistory: (c, url, _) async {
            if (url != null) widget.onUrl?.call(url.toString());
            final canBack = await c.canGoBack();
            if (mounted) setState(() => _canBack = canBack);
          },
          shouldOverrideUrlLoading: (c, action) async {
            final uri = action.request.url;
            if (uri != null && !['http', 'https', 'about', 'data', 'javascript', 'file'].contains(uri.scheme)) {
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
              return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          },
          onDownloadStartRequest: (c, request) async {
            launchUrl(Uri.parse(request.url.toString()), mode: LaunchMode.externalApplication);
          },
        ),
        if (_progress < 1) LinearProgressIndicator(value: _progress, minHeight: 2),
      ],
    );

    if (widget.embedded) {
      return PopScope(
        canPop: !_canBack,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goBack();
        },
        child: body,
      );
    }

    return PopScope(
      canPop: !_canBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
          leading: IconButton(
            icon: Icon(_canBack ? Icons.arrow_back : Icons.close),
            onPressed: () async {
              if (!await _goBack() && context.mounted) Navigator.of(context).pop();
            },
          ),
          actions: [
            if (_canBack)
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
          ],
        ),
        body: SafeArea(top: false, child: body),
      ),
    );
  }
}

import 'package:dio/dio.dart';
import 'package:flangapp_pro/config/config.dart';
import 'package:flangapp_pro/models/app_config.dart';
import 'package:flangapp_pro/services/hex_color.dart';
import 'package:flangapp_pro/views/need_subscribe.dart';
import 'package:flangapp_pro/native/native_router.dart';
import 'package:flangapp_pro/widgets/splash_loader.dart';
import 'package:flutter/material.dart';

class Splashscreen extends StatefulWidget {
  const Splashscreen({super.key});

  @override
  State<Splashscreen> createState() => _SplashscreenState();
}

class _SplashscreenState extends State<Splashscreen> {

  final apiClient = Dio(
    BaseOptions(
      baseUrl: Config.apiUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
      },
    ),
  );

  // A network failure is retried with these pauses before "App not available" is
  // shown: right after boot (a fresh emulator, a phone that just woke up) the
  // network or DNS is often not ready yet, and the first request fails.
  static const List<int> _retryDelays = [1, 2, 3, 5, 8];

  @override
  initState() {
    super.initState();
    _getAppConfig();
  }

  Future<void> _getAppConfig() async {
    for (int attempt = 0; ; attempt++) {
      try {
        final response = await apiClient.get("public/bridge/app?uid=${Config.appUid}");
        if (response.statusCode == 200) {
          AppConfig config = AppConfig.fromJson(response.data);
          _initApp(config);
        } else {
          failLoad();
        }
        return;
      } on DioException catch (e) {
        // The server answered 4xx: the app was removed or its plan has run out —
        // retrying won't change that.
        final status = e.response?.statusCode ?? 0;
        if ((status >= 400 && status < 500) || attempt >= _retryDelays.length) {
          failLoad();
          return;
        }
        await Future.delayed(Duration(seconds: _retryDelays[attempt]));
        if (!mounted) return;
      } catch (e) {
        failLoad();
        return;
      }
    }
  }

  Future<void> _initApp(AppConfig config) async {
    Future.delayed(Duration(seconds: Config.splashDelay), () {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (BuildContext context) => appHome(config)));
    });
  }

  void failLoad() {
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (BuildContext context) => NeedSubscribe()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HexColor.fromHex(Config.splashBackgroundColor),
      body: Container(
        decoration: Config.splashIsBackgroundImage ?
        BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/${Config.splashBackgroundImage}"),
              fit: BoxFit.cover,
            )
        ) : null,
        child: Center(
          child: Config.splashIsDisplayLogo ? Image.asset(
              "assets/${Config.splashLogoImage}",
              width: 110
          ) : null,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const SplashLoader(),
          if (Config.splashTagline.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text(Config.splashTagline, style: TextStyle(
                color: HexColor.fromHex(Config.splashTextColor),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),),
            )
        ],
      ),
    );
  }

}
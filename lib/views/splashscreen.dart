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
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      headers: {
        'Accept': 'application/json',
      },
    ),
  );

  @override
  initState() {
    super.initState();
    _getAppConfig();
  }

  Future<void> _getAppConfig() async {
    try {
      final response = await apiClient.get("public/bridge/app?uid=${Config.appUid}");
      if (response.statusCode == 200) {
        final jsonData = response.data;
        AppConfig config = AppConfig.fromJson(jsonData);
        _initApp(config);
      } else {
        failLoad();
      }
    } on DioException {
      failLoad();
    } catch (e) {
      failLoad();
    }
  }

  Future<void> _initApp(AppConfig config) async {
    Future.delayed(Duration(seconds: Config.splashDelay), () {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (BuildContext context) => appHome(config)));
    });
  }

  void failLoad() {
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
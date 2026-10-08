package pro.flangapp.app.flangapp_pro

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    // Save cookies (the login session) as soon as the app leaves the screen,
    // so closing the app from the recent apps screen doesn't log the user out.
    override fun onPause() {
        super.onPause()
        CookieManager.getInstance().flush()
    }
}

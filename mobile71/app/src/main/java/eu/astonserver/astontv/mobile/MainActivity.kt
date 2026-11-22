package eu.astonserver.astontv.mobile

import android.app.Activity
import android.os.Bundle
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebSettings
import android.widget.FrameLayout

class MainActivity : Activity() {
    private lateinit var web: WebView
    private var fullScreen: View? = null
    private var fullScreenCallback: WebChromeClient.CustomViewCallback? = null
    private lateinit var container: FrameLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = android.graphics.Color.rgb(6, 21, 42)
        window.navigationBarColor = android.graphics.Color.rgb(6, 21, 42)
        container = FrameLayout(this)
        web = WebView(this)
        container.addView(web, FrameLayout.LayoutParams(-1, -1))
        setContentView(container)
        CookieManager.getInstance().setAcceptCookie(true)
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            allowFileAccess = false
            allowContentAccess = false
            setSupportMultipleWindows(false)
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val uri = request.url
                return !(uri.scheme == "https" && uri.host == "tv.astonserver.eu")
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                if (fullScreen != null) { callback.onCustomViewHidden(); return }
                fullScreen = view
                fullScreenCallback = callback
                web.visibility = View.GONE
                container.addView(view, FrameLayout.LayoutParams(-1, -1))
                @Suppress("DEPRECATION")
                run { window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY) }
            }
            override fun onHideCustomView() { exitFullScreen() }
        }
        if (savedInstanceState == null) web.loadUrl("https://tv.astonserver.eu/tv6/")
        else web.restoreState(savedInstanceState)
    }
    private fun exitFullScreen() {
        fullScreen?.let { container.removeView(it) }
        fullScreen = null
        fullScreenCallback?.onCustomViewHidden()
        fullScreenCallback = null
        web.visibility = View.VISIBLE
        @Suppress("DEPRECATION")
        run { window.decorView.systemUiVisibility = 0 }
    }
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (fullScreen != null) exitFullScreen()
        else if (web.canGoBack()) web.goBack()
        else super.onBackPressed()
    }
    override fun onSaveInstanceState(outState: Bundle) { web.saveState(outState); super.onSaveInstanceState(outState) }
    override fun onPause() { web.onPause(); super.onPause() }
    override fun onResume() { super.onResume(); web.onResume() }
    override fun onDestroy() { web.destroy(); super.onDestroy() }
}

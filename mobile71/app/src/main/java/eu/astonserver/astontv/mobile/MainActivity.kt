package eu.astonserver.astontv.mobile

import android.app.Activity
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebSettings
import android.widget.FrameLayout

class MainActivity : Activity() {
    private lateinit var web: WebView
    private lateinit var container: FrameLayout
    private var customView: View? = null
    private var customCallback: WebChromeClient.CustomViewCallback? = null

    @Suppress("DEPRECATION")
    private fun immersive() {
        window.setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN)
        window.navigationBarColor = Color.BLACK
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
        immersive()
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
                val u = request.url
                return !(u.scheme == "https" && u.host == "tv.astonserver.eu")
            }
            override fun onPageFinished(view: WebView, url: String) {
                super.onPageFinished(view, url)
                // Recalculate the TV6 adaptive layout after Android's full-screen insets settle.
                view.evaluateJavascript("try{if(typeof fit==='function')fit();}catch(e){}", null)
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                if (customView != null) { callback.onCustomViewHidden(); return }
                customView = view
                customCallback = callback
                web.visibility = View.GONE
                container.addView(view, FrameLayout.LayoutParams(-1, -1))
                immersive()
            }
            override fun onHideCustomView() { closeCustomView() }
        }
        if (savedInstanceState == null) web.loadUrl("https://tv.astonserver.eu/tv6/")
        else web.restoreState(savedInstanceState)
    }

    private fun closeCustomView() {
        customView?.let { container.removeView(it) }
        customView = null
        customCallback?.onCustomViewHidden()
        customCallback = null
        web.visibility = View.VISIBLE
        immersive()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        immersive()
        web.postDelayed({ web.evaluateJavascript("try{if(typeof fit==='function')fit();window.dispatchEvent(new Event('resize'));}catch(e){}", null) }, 200)
    }

    @Suppress("DEPRECATION")
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) immersive()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        when {
            customView != null -> closeCustomView()
            web.canGoBack() -> web.goBack()
            else -> super.onBackPressed()
        }
    }
    override fun onSaveInstanceState(outState: Bundle) { web.saveState(outState); super.onSaveInstanceState(outState) }
    override fun onPause() { web.onPause(); super.onPause() }
    override fun onResume() { super.onResume(); web.onResume(); immersive() }
    override fun onDestroy() { web.destroy(); super.onDestroy() }
}

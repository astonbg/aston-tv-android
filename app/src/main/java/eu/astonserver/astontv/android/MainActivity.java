package eu.astonserver.astontv.android;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.net.URI;

public final class MainActivity extends Activity {
    private static final String LOCAL = "http://10.10.10.179:8424/";
    private static final String PUBLIC = "https://tv.astonserver.eu/";
    private WebView web;
    private FrameLayout root, fullscreen;
    private View custom;
    private WebChromeClient.CustomViewCallback callback;
    private String current;
    private TextView title;

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        getWindow().setStatusBarColor(Color.rgb(12, 16, 24));
        root = new FrameLayout(this);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setBackgroundColor(Color.rgb(12, 16, 24));
        root.addView(layout, new FrameLayout.LayoutParams(-1, -1));

        LinearLayout bar = new LinearLayout(this);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setBackgroundColor(Color.rgb(24, 29, 41));
        layout.addView(bar, new LinearLayout.LayoutParams(-1, dp(52)));
        bar.addView(button("⌂", () -> load(current)));
        bar.addView(button("‹", this::back));
        bar.addView(button("↻", () -> web.reload()));
        title = new TextView(this);
        title.setText("ASTON TV 4.0 PREMIUM");
        title.setTextSize(14);
        title.setTextColor(Color.WHITE);
        title.setGravity(Gravity.CENTER_VERTICAL);
        bar.addView(title, new LinearLayout.LayoutParams(0, -1, 1));
        bar.addView(button("⚙", this::chooseServer));

        web = new WebView(this);
        web.setBackgroundColor(Color.rgb(12, 16, 24));
        web.setFocusable(true);
        web.setFocusableInTouchMode(true);
        layout.addView(web, new LinearLayout.LayoutParams(-1, 0, 1));
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false);
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest request) {
                return !allowed(request.getUrl().toString());
            }
            @Override public void onPageFinished(WebView v, String url) {
                title.setText(url.startsWith("https:") ? "ASTON TV · ВЪНШЕН" : "ASTON TV · ЛОКАЛЕН");
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override public void onShowCustomView(View view, CustomViewCallback cb) {
                if (custom != null) { cb.onCustomViewHidden(); return; }
                custom = view;
                callback = cb;
                fullscreen = new FrameLayout(MainActivity.this);
                fullscreen.setBackgroundColor(Color.BLACK);
                fullscreen.addView(view, new FrameLayout.LayoutParams(-1, -1));
                root.addView(fullscreen, new FrameLayout.LayoutParams(-1, -1));
                getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
            }
            @Override public void onHideCustomView() { hideFullscreen(); }
        });
        setContentView(root);
        current = getPreferences(MODE_PRIVATE).getString("server", LOCAL);
        load(current);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private Button button(String label, Runnable action) {
        Button b = new Button(this);
        b.setText(label);
        b.setTextColor(Color.WHITE);
        b.setAllCaps(false);
        b.setTextSize(19);
        b.setBackgroundTintList(android.content.res.ColorStateList.valueOf(Color.rgb(39, 46, 62)));
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(dp(52), -1);
        b.setLayoutParams(p);
        b.setOnClickListener(v -> action.run());
        return b;
    }

    private boolean allowed(String value) {
        try {
            URI uri = new URI(value);
            if ("https".equalsIgnoreCase(uri.getScheme()) && "tv.astonserver.eu".equalsIgnoreCase(uri.getHost())) return true;
            return "http".equalsIgnoreCase(uri.getScheme()) && "10.10.10.179".equals(uri.getHost()) && uri.getPort() == 8424;
        } catch (Exception ex) {
            return false;
        }
    }

    private void load(String target) {
        if (!allowed(target)) { chooseServer(); return; }
        current = target;
        getPreferences(MODE_PRIVATE).edit().putString("server", target).apply();
        web.loadUrl(target);
    }

    private void chooseServer() {
        String[] servers = { "Локален Premium — 10.10.10.179:8424", "Външен портал — tv.astonserver.eu" };
        new AlertDialog.Builder(this)
            .setTitle("Aston TV — сървър")
            .setItems(servers, (dialog, which) -> load(which == 0 ? LOCAL : PUBLIC))
            .setNegativeButton("Отказ", null).show();
    }

    private void hideFullscreen() {
        if (custom == null) return;
        root.removeView(fullscreen);
        fullscreen = null;
        custom = null;
        if (callback != null) callback.onCustomViewHidden();
        callback = null;
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
    }

    private void back() {
        if (custom != null) { hideFullscreen(); return; }
        web.evaluateJavascript("(function(){try{if(typeof pairingVisible==='function'&&pairingVisible()){if(typeof pairUpdate==='function')pairUpdate('back');return 'ok';}if(typeof remoteBack==='function'){remoteBack();return 'ok';}}catch(e){}return 'none';})()", result -> {
            if ("\"none\"".equals(result) && web.canGoBack()) web.goBack();
        });
    }

    @Override public void onBackPressed() { back(); }
    @Override public boolean dispatchKeyEvent(KeyEvent event) {
        if (event.getAction() == KeyEvent.ACTION_DOWN) {
            if (event.getKeyCode() == KeyEvent.KEYCODE_BACK || event.getKeyCode() == KeyEvent.KEYCODE_ESCAPE) {
                back();
                return true;
            }
            if (event.getKeyCode() == KeyEvent.KEYCODE_MENU) {
                chooseServer();
                return true;
            }
        }
        return super.dispatchKeyEvent(event);
    }
    @Override protected void onPause() { super.onPause(); if (web != null) web.onPause(); }
    @Override protected void onResume() { super.onResume(); if (web != null) web.onResume(); }
    @Override protected void onDestroy() { if (web != null) web.destroy(); super.onDestroy(); }
}

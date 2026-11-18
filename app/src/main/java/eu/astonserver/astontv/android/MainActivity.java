package eu.astonserver.astontv.android;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.res.ColorStateList;
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
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import org.json.JSONArray;
import org.json.JSONObject;
import org.json.JSONTokener;
import java.net.URI;

public final class MainActivity extends Activity {
    private static final String LOCAL = "http://10.10.10.179:8424/";
    private static final String PUBLIC = "https://tv.astonserver.eu/";
    private final int bg=Color.rgb(14,18,28), panel=Color.rgb(28,35,49), accent=Color.rgb(56,83,127);
    private WebView web;
    private FrameLayout root, fullscreen;
    private View custom;
    private WebChromeClient.CustomViewCallback customCallback;
    private String current;
    private TextView title;
    private long lastBack = 0;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(bg);
        getWindow().setNavigationBarColor(bg);
        root=new FrameLayout(this);
        LinearLayout shell=new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setBackgroundColor(bg);
        root.addView(shell,new FrameLayout.LayoutParams(-1,-1));

        LinearLayout header=new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setBackgroundColor(panel);
        shell.addView(header,new LinearLayout.LayoutParams(-1,dp(48)));
        header.addView(makeButton("⌂",this::home),new LinearLayout.LayoutParams(dp(46),-1));
        title=new TextView(this);
        title.setText("ASTON TV 4.1 PREMIUM");
        title.setTextColor(Color.WHITE);
        title.setTextSize(14);
        title.setGravity(Gravity.CENTER_VERTICAL);
        title.setSingleLine(true);
        header.addView(title,new LinearLayout.LayoutParams(0,-1,1));
        header.addView(makeButton("↻",()->web.reload()),new LinearLayout.LayoutParams(dp(46),-1));
        header.addView(makeButton("⚙",this::chooseServer),new LinearLayout.LayoutParams(dp(46),-1));

        web=new WebView(this);
        web.setBackgroundColor(bg);
        web.setFocusable(true);
        web.setFocusableInTouchMode(true);
        shell.addView(web,new LinearLayout.LayoutParams(-1,0,1));
        WebSettings settings=web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setSupportMultipleWindows(false);
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web,false);
        web.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest req){
                String url=req.getUrl().toString();
                if(!allowed(url)){Toast.makeText(MainActivity.this,"Външният адрес е блокиран",Toast.LENGTH_SHORT).show();return true;}
                return false;
            }
            @Override public void onPageFinished(WebView v,String url){
                title.setText(url.startsWith("https:")?"ASTON TV · ВЪНШЕН":"ASTON TV · PREMIUM");
            }
        });
        web.setWebChromeClient(new WebChromeClient(){
            @Override public void onShowCustomView(View view,CustomViewCallback cb){
                if(custom!=null){cb.onCustomViewHidden();return;}
                custom=view;customCallback=cb;
                fullscreen=new FrameLayout(MainActivity.this);
                fullscreen.setBackgroundColor(Color.BLACK);
                fullscreen.addView(view,new FrameLayout.LayoutParams(-1,-1));
                root.addView(fullscreen,new FrameLayout.LayoutParams(-1,-1));
                getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
            }
            @Override public void onHideCustomView(){hideFullscreen();}
        });

        HorizontalScrollView scroller=new HorizontalScrollView(this);
        scroller.setHorizontalScrollBarEnabled(false);
        scroller.setFillViewport(false);
        scroller.setBackgroundColor(panel);
        LinearLayout controls=new LinearLayout(this);
        controls.setGravity(Gravity.CENTER_VERTICAL);
        controls.setPadding(dp(4),dp(4),dp(4),dp(4));
        scroller.addView(controls);
        shell.addView(scroller,new LinearLayout.LayoutParams(-1,dp(64)));
        addControl(controls,"◀ Канал",()->changeChannel(-1));
        addControl(controls,"Канал ▶",()->changeChannel(1));
        addControl(controls,"Канали",this::pickChannel);
        addControl(controls,"−10 сек",()->seek(-10));
        addControl(controls,"+10 сек",()->seek(10));
        addControl(controls,"▶ / ❚❚",this::togglePlayback);
        addControl(controls,"EPG",()->navigate("guide"));
        addControl(controls,"Камери",()->navigate("cameras"));
        addControl(controls,"⛶",this::fullScreen);

        setContentView(root);
        current=getPreferences(MODE_PRIVATE).getString("server",LOCAL);
        load(current);
    }

    private int dp(int x){return Math.round(x*getResources().getDisplayMetrics().density);}
    private Button makeButton(String text,Runnable task){
        Button b=new Button(this);
        b.setText(text);
        b.setAllCaps(false);
        b.setTextSize(14);
        b.setTextColor(Color.WHITE);
        b.setMinWidth(0);
        b.setMinimumWidth(0);
        b.setPadding(dp(8),0,dp(8),0);
        b.setBackgroundTintList(ColorStateList.valueOf(accent));
        b.setOnClickListener(v->task.run());
        b.setFocusable(true);
        return b;
    }
    private void addControl(LinearLayout row,String name,Runnable action){
        Button b=makeButton(name,action);
        LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-2,dp(50));
        p.setMargins(dp(3),0,dp(3),0);
        row.addView(b,p);
    }
    private void js(String command){
        if(web!=null)web.evaluateJavascript(command,null);
    }
    private void toast(String msg){Toast.makeText(this,msg,Toast.LENGTH_SHORT).show();}
    private void navigate(String section){
        js("(function(){if(typeof setView==='function'){setView('"+section+"');return;} var b=document.querySelector('[data-view=\""+section+"\"]'); if(b)b.click();})()");
    }
    private void home(){navigate("home");}
    private void changeChannel(int step){
        js("(function(){if(typeof changeChannel==='function' && typeof s!=='undefined' && s.playingChannel){changeChannel("+step+");return;}if(typeof s!=='undefined'&&s.channels&&s.channels.length&&typeof startChannel==='function'){startChannel(s.channels[0].id,'auto');return;}alert('Няма избран или зареден канал');})()");
    }
    private void seek(int seconds){
        web.evaluateJavascript("(function(){var v=document.querySelector('video');if(!v||!v.seekable||!v.seekable.length)return 'no';try{var a=v.seekable.start(0),b=v.seekable.end(v.seekable.length-1);if(!isFinite(a)||!isFinite(b)||b-a<2)return 'no';var t=Math.min(b,Math.max(a,v.currentTime+("+seconds+")));v.currentTime=t;return 'ok';}catch(e){return 'no';}})()",r->{
            if(!"\"ok\"".equals(r))toast("Този поток не позволява превъртане");
        });
    }
    private void togglePlayback(){
        web.evaluateJavascript("(function(){var v=document.querySelector('video');if(!v)return 'no';if(v.paused){v.play().catch(function(){});return 'play';}v.pause();return 'pause';})()",r->{
            if("\"no\"".equals(r))toast("Първо избери канал или филм");
        });
    }
    private void fullScreen(){
        js("(function(){var v=document.querySelector('video');if(v&&v.requestFullscreen){v.requestFullscreen().catch(function(){});return;}var b=document.querySelector('#fullscreen');if(b)b.click();})()");
    }
    private void pickChannel(){
        web.evaluateJavascript("(function(){if(typeof s==='undefined'||!s.channels)return '[]';return JSON.stringify(s.channels.map(function(c){return {id:String(c.id),name:String(c.name||c.id),number:String(c.number||'')}}));})()",raw->{
            try{
                Object decoded=new JSONTokener(raw).nextValue();
                JSONArray channels=new JSONArray(String.valueOf(decoded));
                if(channels.length()==0){toast("Няма заредени канали");return;}
                String[] labels=new String[channels.length()];
                for(int i=0;i<channels.length();i++){
                    JSONObject c=channels.getJSONObject(i);
                    labels[i]=c.optString("number")+"  "+c.optString("name");
                }
                new AlertDialog.Builder(this).setTitle("Избери канал")
                    .setItems(labels,(d,which)->{
                        String id=channels.optJSONObject(which).optString("id","");
                        String safe=JSONObject.quote(id);
                        js("(function(){if(typeof startChannel==='function')startChannel("+safe+",'auto');})()");
                    }).setNegativeButton("Отказ",null).show();
            }catch(Exception e){toast("Зареди Premium Gateway 4.0 и опитай пак");}
        });
    }
    private boolean allowed(String value){
        try{
            URI u=new URI(value);
            if("https".equalsIgnoreCase(u.getScheme())&&"tv.astonserver.eu".equalsIgnoreCase(u.getHost()))return true;
            return "http".equalsIgnoreCase(u.getScheme())&&"10.10.10.179".equals(u.getHost())&&u.getPort()==8424;
        }catch(Exception e){return false;}
    }
    private void load(String target){
        if(!allowed(target)){chooseServer();return;}
        current=target;
        getPreferences(MODE_PRIVATE).edit().putString("server",target).apply();
        web.loadUrl(target);
    }
    private void chooseServer(){
        new AlertDialog.Builder(this).setTitle("Aston TV — сървър")
            .setItems(new String[]{"Локален Premium 4.0 — 10.10.10.179:8424","Външен портал — tv.astonserver.eu"},
                (d,which)->load(which==0?LOCAL:PUBLIC))
            .setNegativeButton("Отказ",null).show();
    }
    private void hideFullscreen(){
        if(custom==null)return;
        root.removeView(fullscreen);fullscreen=null;custom=null;
        if(customCallback!=null)customCallback.onCustomViewHidden();
        customCallback=null;
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
    }
    private void back(){
        if(custom!=null){hideFullscreen();return;}
        web.evaluateJavascript("(function(){try{if(typeof pairingVisible==='function'&&pairingVisible()){if(typeof pairUpdate==='function')pairUpdate('back');return 'ok';}if(typeof remoteBack==='function'){remoteBack();return 'ok';}}catch(e){}return 'none';})()",r->{
            if("\"none\"".equals(r)){
                if(web.canGoBack())web.goBack();
                else{
                    long now=System.currentTimeMillis();
                    if(now-lastBack<1800)finish();
                    else {lastBack=now;toast("Натисни Назад отново за изход");}
                }
            }
        });
    }
    @Override public void onBackPressed(){back();}
    @Override public boolean dispatchKeyEvent(KeyEvent e){
        if(e.getAction()==KeyEvent.ACTION_DOWN){
            int key=e.getKeyCode();
            if(key==KeyEvent.KEYCODE_BACK||key==KeyEvent.KEYCODE_ESCAPE){back();return true;}
            if(key==KeyEvent.KEYCODE_MENU){chooseServer();return true;}
            if(key==KeyEvent.KEYCODE_MEDIA_NEXT){changeChannel(1);return true;}
            if(key==KeyEvent.KEYCODE_MEDIA_PREVIOUS){changeChannel(-1);return true;}
        }
        return super.dispatchKeyEvent(e);
    }
    @Override protected void onPause(){if(web!=null)web.onPause();super.onPause();}
    @Override protected void onResume(){super.onResume();if(web!=null)web.onResume();}
    @Override protected void onDestroy(){if(web!=null)web.destroy();super.onDestroy();}
}

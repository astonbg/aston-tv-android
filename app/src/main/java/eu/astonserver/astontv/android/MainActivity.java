package eu.astonserver.astontv.android;
import android.app.*;
import android.content.*;
import android.content.res.Configuration;
import android.graphics.Color;
import android.os.*;
import android.text.*;
import android.view.*;
import android.widget.*;
import android.webkit.CookieManager;
import androidx.media3.common.*;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.ui.*;
import org.json.*;
import java.util.*;
import java.util.concurrent.*;

@UnstableApi
public final class MainActivity extends Activity {
    private final int bg=Color.rgb(10,14,22),panel=Color.rgb(28,36,48),teal=Color.rgb(61,204,232);
    private final ExecutorService io=Executors.newSingleThreadExecutor();
    private final Handler main=new Handler(Looper.getMainLooper());
    private SharedPreferences prefs;
    GatewayClient api;
    ExoPlayer player;
    PlayerView playerView;
    FrameLayout video;
    private LinearLayout shell,header,bottom,details,catalog,rows;
    private TextView status,title;
    private Button fit;
    private EditText search;
    private JSONArray channels=new JSONArray(),cameras=new JSONArray();
    private JSONObject selected;
    private boolean cameraTab,selectedCamera,manualFull,suppressLandscape,fill,paired,foreground,destroyed;
    private String filter="Всички";
    private volatile int generation;
    private long lastBack;
    private Runnable refreshTicket;
    private Set<String> favorites;
    private List<String> recent;
    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        prefs=getSharedPreferences("aston.mobile",MODE_PRIVATE);fill=prefs.getBoolean("fill",true);
        favorites=new HashSet<>(prefs.getStringSet("favorites",Collections.emptySet()));recent=new ArrayList<>();
        try{JSONArray r=new JSONArray(prefs.getString("recent","[]"));for(int i=0;i<r.length();i++)recent.add(r.getString(i));}catch(Exception ignored){}
        String server=prefs.getString("server",GatewayClient.LOCAL);if(!server.equals(GatewayClient.REMOTE))server=GatewayClient.LOCAL;
        if(BuildConfig.DEBUG){String test=getIntent().getStringExtra("test_server");if(test!=null&&test.matches("http://127\\.0\\.0\\.1:[0-9]+/"))server=test;}
        api=new GatewayClient(server);CookieManager.getInstance().setAcceptCookie(true);
        player=new ExoPlayer.Builder(this).build();
        player.setAudioAttributes(new AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),true);
        player.setHandleAudioBecomingNoisy(true);buildUI();
        player.addListener(new Player.Listener(){
            @Override public void onPlaybackStateChanged(int state){if(selected==null)return;if(state==Player.STATE_BUFFERING)status.setText("Буфериране…");else if(state==Player.STATE_READY)status.setText(player.getPlayWhenReady()?"Възпроизвеждане":"Пауза");else if(state==Player.STATE_ENDED)status.setText("Потокът завърши · избери Повтори");}
            @Override public void onIsPlayingChanged(boolean playing){video.setKeepScreenOn(playing);if(playing)status.setText("НА ЖИВО");else if(player.getPlaybackState()==Player.STATE_READY)status.setText("Пауза");}
            @Override public void onPlayerError(PlaybackException error){status.setText("Видеото не тръгна · "+error.getErrorCodeName());manualFull=false;suppressLandscape=true;layout();playerView.showController();}
        });connect();
    }
    private int dp(int v){return Math.round(v*getResources().getDisplayMetrics().density);}
    private TextView label(String value,int size){TextView v=new TextView(this);v.setText(value);v.setTextColor(Color.WHITE);v.setTextSize(size);v.setPadding(dp(10),dp(4),dp(10),dp(4));return v;}
    private Button button(String value,Runnable action){Button b=new Button(this);b.setText(value);b.setTextSize(14);b.setAllCaps(false);b.setTextColor(Color.WHITE);b.setMinWidth(0);b.setMinimumWidth(0);b.setPadding(dp(8),0,dp(8),0);b.setMinHeight(dp(48));b.setBackgroundTintList(android.content.res.ColorStateList.valueOf(panel));b.setOnClickListener(v->action.run());return b;}
    private void add(LinearLayout row,View v){row.addView(v,new LinearLayout.LayoutParams(0,dp(50),1));}
    private LinearLayout vertical(){LinearLayout v=new LinearLayout(this);v.setOrientation(LinearLayout.VERTICAL);return v;}
    private void buildUI(){
        shell=vertical();shell.setBackgroundColor(bg);setContentView(shell);shell.setFitsSystemWindows(true);
        header=new LinearLayout(this);header.setGravity(Gravity.CENTER_VERTICAL);TextView logo=label("ASTON TV · MOBILE",18);logo.setTextColor(teal);header.addView(logo,new LinearLayout.LayoutParams(0,dp(50),1));header.addView(button("↻",this::connect),new LinearLayout.LayoutParams(dp(52),dp(50)));shell.addView(header);
        video=new FrameLayout(this);video.setContentDescription("Видео зона");video.setBackgroundColor(Color.BLACK);
        playerView=new PlayerView(this);playerView.setPlayer(player);playerView.setControllerShowTimeoutMs(4000);playerView.setShowNextButton(false);playerView.setShowPreviousButton(false);video.addView(playerView,new FrameLayout.LayoutParams(-1,-1));
        playerView.setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS);
        LinearLayout overlay=new LinearLayout(this);overlay.setGravity(Gravity.END);
        overlay.addView(button("◀",()->step(-1)),new LinearLayout.LayoutParams(dp(48),dp(48)));
        overlay.addView(button("▶",()->step(1)),new LinearLayout.LayoutParams(dp(48),dp(48)));
        fit=button(fill?"Цял кадър":"Запълни",()->{fill=!fill;prefs.edit().putBoolean("fill",fill).apply();updateFit();});
        Button full=button("⛶",this::toggleFull);full.setContentDescription("Цял екран / Списък");overlay.addView(fit);overlay.addView(full,new LinearLayout.LayoutParams(dp(64),dp(48)));
        video.addView(overlay,new FrameLayout.LayoutParams(-2,dp(48),Gravity.TOP|Gravity.RIGHT));
        playerView.setControllerVisibilityListener((PlayerView.ControllerVisibilityListener)visibility->overlay.setVisibility(visibility));shell.addView(video,new LinearLayout.LayoutParams(-1,dp(280)));
        details=vertical();title=label("Избери канал или камера",18);status=label("Свързване…",12);status.setTextColor(teal);details.addView(title);details.addView(status);
        LinearLayout controls=new LinearLayout(this);add(controls,button("◀",()->step(-1)));add(controls,button("Списък",()->{manualFull=false;suppressLandscape=true;layout();}));add(controls,button("Повтори",()->{if(selected!=null)play(selected,selectedCamera);}));add(controls,button("▶",()->step(1)));add(controls,button("Стоп",this::stop));details.addView(controls);shell.addView(details);
        catalog=vertical();search=new EditText(this);search.setSingleLine(true);search.setTextColor(Color.WHITE);search.setHintTextColor(Color.LTGRAY);search.setHint("Търси канал или камера");catalog.addView(search,new LinearLayout.LayoutParams(-1,dp(48)));
        search.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int a,int c,int f){}public void onTextChanged(CharSequence s,int a,int b,int c){renderRows();}public void afterTextChanged(Editable e){}});
        LinearLayout filters=new LinearLayout(this);for(String f:new String[]{"Всички","Любими","Последни"})add(filters,button(f,()->{filter=f;renderRows();}));catalog.addView(filters);
        ScrollView scroll=new ScrollView(this);rows=vertical();scroll.addView(rows);catalog.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));shell.addView(catalog,new LinearLayout.LayoutParams(-1,0,1));
        bottom=new LinearLayout(this);add(bottom,button("Телевизия",()->tab(false)));add(bottom,button("Камери",()->tab(true)));add(bottom,button("Настройки",this::settings));shell.addView(bottom);
        updateFit();shell.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->{if(r-l!=or-ol||b-t!=ob-ot)layout();});shell.post(this::layout);
    }
    private void updateFit(){playerView.setResizeMode(fill?AspectRatioFrameLayout.RESIZE_MODE_ZOOM:AspectRatioFrameLayout.RESIZE_MODE_FIT);fit.setText(fill?"Цял кадър":"Запълни");}
    private boolean landscape(){return getResources().getConfiguration().orientation==Configuration.ORIENTATION_LANDSCAPE;}
    boolean isFull(){return selected!=null&&(manualFull||(landscape()&&!suppressLandscape));}
    private void layout(){
        if(shell==null)return;boolean full=isFull();int height=shell.getHeight();if(height<=0)return;boolean compact=landscape()&&!full;
        header.setVisibility(full||compact?View.GONE:View.VISIBLE);details.setVisibility(full?View.GONE:View.VISIBLE);title.setVisibility(compact?View.GONE:View.VISIBLE);catalog.setVisibility(full?View.GONE:View.VISIBLE);bottom.setVisibility(full?View.GONE:View.VISIBLE);
        int size=full?height:Math.max(dp(compact?90:200),(int)(height*(compact?0.25:0.44)));if(video.getLayoutParams().height!=size){video.getLayoutParams().height=size;video.requestLayout();}
        getWindow().getDecorView().setSystemUiVisibility(full?View.SYSTEM_UI_FLAG_FULLSCREEN|View.SYSTEM_UI_FLAG_HIDE_NAVIGATION|View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY:View.SYSTEM_UI_FLAG_VISIBLE);
    }
    private void toggleFull(){if(isFull()){manualFull=false;suppressLandscape=true;}else{manualFull=true;suppressLandscape=false;}layout();playerView.showController();}
    @Override public void onConfigurationChanged(Configuration config){super.onConfigurationChanged(config);manualFull=false;suppressLandscape=false;shell.post(this::layout);}
    private void tab(boolean camera){cameraTab=camera;filter="Всички";manualFull=false;suppressLandscape=true;search.setText("");renderRows();layout();}
    private String name(JSONObject item,boolean cam){return cam?prefs.getString("camera."+item.optString("id"),item.optString("name","Камера")):item.optString("name","Канал");}
    private void renderRows(){
        if(rows==null)return;rows.removeAllViews();JSONArray data=cameraTab?cameras:channels;List<JSONObject> list=new ArrayList<>();for(int i=0;i<data.length();i++)if(data.optJSONObject(i)!=null)list.add(data.optJSONObject(i));
        if(!cameraTab&&filter.equals("Последни"))list.sort(Comparator.comparingInt(c->{int n=recent.indexOf(c.optString("id"));return n<0?Integer.MAX_VALUE:n;}));
        String query=search.getText().toString().toLowerCase(Locale.ROOT);
        for(JSONObject item:list){String id=item.optString("id"),name=name(item,cameraTab);if(!name.toLowerCase(Locale.ROOT).contains(query))continue;if(!cameraTab&&filter.equals("Любими")&&!favorites.contains(id))continue;if(!cameraTab&&filter.equals("Последни")&&!recent.contains(id))continue;boolean cam=cameraTab;
            LinearLayout row=new LinearLayout(this);row.setGravity(Gravity.CENTER_VERTICAL);String now=item.optJSONObject("now")==null?"":item.optJSONObject("now").optString("title");
            Button open=button(name+(now.isEmpty()?"":"\n"+now),()->play(item,cam));open.setGravity(Gravity.LEFT|Gravity.CENTER_VERTICAL);open.setEnabled(!cam||GatewayClient.enabled(item.opt("enabled")));row.addView(open,new LinearLayout.LayoutParams(0,dp(64),1));
            if(!cam)open.setOnLongClickListener(v->{JSONObject next=item.optJSONObject("next");new AlertDialog.Builder(this).setTitle(name).setMessage("СЕГА\n"+(now.isEmpty()?"Няма данни":now)+"\n\nСЛЕДВА\n"+(next==null?"Няма данни":next.optString("title","Няма данни"))).setPositiveButton("Затвори",null).show();return true;});
            row.addView(button(cam?"✎":favorites.contains(id)?"★":"☆",()->{if(cam)rename(item);else{if(!favorites.add(id))favorites.remove(id);prefs.edit().putStringSet("favorites",new HashSet<>(favorites)).apply();renderRows();}}),new LinearLayout.LayoutParams(dp(56),dp(64)));rows.addView(row);
        }if(rows.getChildCount()==0)rows.addView(label(paired?"Няма елементи за този филтър":"Няма зареден списък · отвори Настройки",15));
    }
    private void rename(JSONObject item){EditText input=new EditText(this);input.setSingleLine(true);input.setText(name(item,true));new AlertDialog.Builder(this).setTitle("Име на камерата").setView(input).setPositiveButton("Запази",(d,w)->{String s=input.getText().toString().trim();prefs.edit().putString("camera."+item.optString("id"),s.isEmpty()?item.optString("name"):s.substring(0,Math.min(60,s.length()))).apply();renderRows();if(selectedCamera&&selected!=null)title.setText(name(selected,true));}).setNegativeButton("Отказ",null).show();}
    private interface Work {JSONObject run(GatewayClient client)throws Exception;}
    private interface Result {void accept(JSONObject value);}
    private void request(Work work,Result result){request(work,result,-1);}
    private void request(Work work,Result result,int expected){
        final GatewayClient client=api;
        io.execute(()->{
            if(expected>=0&&expected!=generation)return;
            try{JSONObject data=work.run(client);main.post(()->{if(!destroyed&&api==client&&(expected<0||expected==generation))result.accept(data);});}
            catch(Exception e){main.post(()->{
                if(destroyed||api!=client||(expected>=0&&expected!=generation))return;
                status.setText(e instanceof GatewayClient.Failure?e.getMessage():"Няма връзка със сървъра. Провери Wi-Fi/VPN или външния адрес.");
                if(expected>=0){manualFull=false;suppressLandscape=true;layout();}
                if(e instanceof GatewayClient.Failure&&((GatewayClient.Failure)e).status==401){paired=false;pairDialog();}
            });}
        });
    }
    private void connect(){status.setText("Проверка на връзката…");request(c->c.request("api/public/me",null),me->{paired=true;reload();});}
    private void reload(){
        request(c->c.request("api/public/channels",null),r->{channels=r.optJSONArray("channels");if(channels==null)channels=new JSONArray();renderRows();if(selected==null)status.setText("Заредени "+channels.length()+" канала");if(selected==null&&prefs.getBoolean("resume",false)){String last=prefs.getString("last","");for(int i=0;i<channels.length();i++)if(last.equals(channels.optJSONObject(i).optString("id"))){play(channels.optJSONObject(i),false);break;}}});
        request(c->c.request("api/public/cameras",null),r->{cameras=r.optJSONArray("cameras");if(cameras==null)cameras=new JSONArray();renderRows();});
    }
    void play(JSONObject item,boolean camera){
        if(camera&&!GatewayClient.enabled(item.opt("enabled")))return;selected=item;selectedCamera=camera;cameraTab=camera;int seq=++generation;if(refreshTicket!=null)main.removeCallbacks(refreshTicket);
        player.stop();player.clearMediaItems();title.setText(name(item,camera));status.setText("Зареждане…");suppressLandscape=false;layout();playerView.showController();
        if(!camera){String id=item.optString("id");recent.remove(id);recent.add(0,id);if(recent.size()>20)recent.remove(recent.size()-1);prefs.edit().putString("recent",new JSONArray(recent).toString()).putString("last",id).apply();}
        request(c->{JSONObject body=new JSONObject();body.put(camera?"camera":"channel_id",item.getString("id"));body.put("format",camera?"hls":"auto");return c.request(camera?"api/public/camera-play":"api/public/play",body);},r->{
            if(seq!=generation)return;try{String url=api.mediaUrl(r.getString("url"));DefaultHttpDataSource.Factory http=new DefaultHttpDataSource.Factory().setConnectTimeoutMs(10000).setReadTimeoutMs(30000).setAllowCrossProtocolRedirects(false);
                String cookies=CookieManager.getInstance().getCookie(api.base);if(cookies!=null)http.setDefaultRequestProperties(Collections.singletonMap("Cookie",cookies));
                MediaItem media=new MediaItem.Builder().setUri(url).setMimeType(camera||"hls".equals(r.optString("format"))?MimeTypes.APPLICATION_M3U8:MimeTypes.VIDEO_MP2T).build();
                player.setMediaSource(new DefaultMediaSourceFactory(http).createMediaSource(media));player.prepare();player.setPlayWhenReady(foreground);
                refreshTicket=()->{if(seq==generation&&selected!=null&&foreground)play(selected,selectedCamera);};main.postDelayed(refreshTicket,23*60*1000);
            }catch(Exception e){status.setText("Невалиден видео адрес от Gateway");}
        },seq);renderRows();
    }
    private void step(int delta){JSONArray source=selectedCamera?cameras:channels;List<JSONObject> list=new ArrayList<>();for(int i=0;i<source.length();i++){JSONObject c=source.optJSONObject(i);if(c!=null&&(!selectedCamera||GatewayClient.enabled(c.opt("enabled"))))list.add(c);}if(list.isEmpty())return;int index=-1;for(int i=0;i<list.size();i++)if(selected!=null&&list.get(i).optString("id").equals(selected.optString("id")))index=i;play(list.get((index+delta+list.size())%list.size()),selectedCamera);}
    private void stop(){generation++;if(refreshTicket!=null)main.removeCallbacks(refreshTicket);player.stop();player.clearMediaItems();selected=null;manualFull=false;suppressLandscape=false;title.setText("Избери канал или камера");status.setText("Спряно");layout();}
    private void pairDialog(){
        if(isFinishing()||destroyed)return;EditText code=new EditText(this);code.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);code.setFilters(new InputFilter[]{new InputFilter.LengthFilter(8)});code.setHint("8-цифрен код от Aston Studio");
        AlertDialog dialog=new AlertDialog.Builder(this).setTitle("Сдвояване").setView(code).setPositiveButton("Свържи",null).setNegativeButton("Отказ",null).create();dialog.show();dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->{String value=code.getText().toString();if(!value.matches("[0-9]{8}")){code.setError("Нужни са 8 цифри");return;}dialog.dismiss();request(c->c.request("api/public/pair",new JSONObject().put("code",value)),r->connect());});
    }
    private void settings(){String[] options={"Домашен сървър (Wi-Fi/VPN)","Външен сървър (интернет)","Сдвояване с код","Обнови списъците",prefs.getBoolean("resume",false)?"Изключи последния канал при отваряне":"Продължи последния канал при отваряне","Диагностика"};
        new AlertDialog.Builder(this).setTitle("Настройки · 5.3.0").setItems(options,(d,n)->{if(n<2){stop();api=new GatewayClient(n==0?GatewayClient.LOCAL:GatewayClient.REMOTE);prefs.edit().putString("server",api.base).apply();paired=false;channels=new JSONArray();cameras=new JSONArray();renderRows();connect();}else if(n==2)pairDialog();else if(n==3)connect();else if(n==4)prefs.edit().putBoolean("resume",!prefs.getBoolean("resume",false)).apply();else request(c->c.request("healthz",null),r->new AlertDialog.Builder(this).setTitle("Връзка").setMessage("Gateway: "+r.optString("version","?")+"\n"+api.base+"\nСдвоено: "+paired+"\nКанали: "+channels.length()+" · Камери: "+cameras.length()+"\nДомашният адрес изисква домашен Wi-Fi или VPN.").setPositiveButton("OK",null).show());}).setNegativeButton("Затвори",null).show();
    }
    @Override public void onBackPressed(){if(isFull()){manualFull=false;suppressLandscape=true;layout();return;}long now=System.currentTimeMillis();if(now-lastBack<1800)super.onBackPressed();else{lastBack=now;Toast.makeText(this,"Назад отново за изход",Toast.LENGTH_SHORT).show();}}
    @Override public boolean dispatchKeyEvent(KeyEvent e){if(e.getAction()==KeyEvent.ACTION_DOWN){switch(e.getKeyCode()){case KeyEvent.KEYCODE_MEDIA_NEXT:step(1);return true;case KeyEvent.KEYCODE_MEDIA_PREVIOUS:step(-1);return true;case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE:if(player.isPlaying())player.pause();else player.play();return true;}}return super.dispatchKeyEvent(e);}
    @Override protected void onResume(){super.onResume();foreground=true;}
    @Override protected void onPause(){foreground=false;player.pause();super.onPause();}
    @Override protected void onDestroy(){destroyed=true;generation++;main.removeCallbacksAndMessages(null);io.shutdownNow();playerView.setPlayer(null);player.release();super.onDestroy();}
}

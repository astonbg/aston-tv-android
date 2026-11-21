package eu.astonserver.astontv.android;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.graphics.Bitmap;
import android.os.Environment;
import androidx.test.core.app.ActivityScenario;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import okhttp3.mockwebserver.*;
import okio.Buffer;
import org.json.JSONObject;
import org.junit.*;
import org.junit.runner.RunWith;
import java.io.*;
import java.util.concurrent.*;
import static org.junit.Assert.*;

@UnstableApi @RunWith(AndroidJUnit4.class)
public class PlaybackTest {
    private MockWebServer server;
    private byte[] transport;
    private volatile boolean cookieSeen;
    @Before public void setup()throws Exception {
        try(InputStream in=InstrumentationRegistry.getInstrumentation().getContext().getAssets().open("sample.ts");ByteArrayOutputStream out=new ByteArrayOutputStream()) {byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1)out.write(b,0,n);transport=out.toByteArray();}
        server=new MockWebServer();
        server.setDispatcher(new Dispatcher(){@Override public MockResponse dispatch(RecordedRequest r){
            String p=r.getPath();
            if(p.equals("/api/public/me"))return json("{}").addHeader("Set-Cookie","aston_public_sid=fixture; Path=/; HttpOnly");
            if(p.equals("/api/public/channels"))return json("{\"channels\":[{\"id\":\"one\",\"name\":\"Тест телевизия\"}]}");
            if(p.equals("/api/public/cameras"))return json("{\"cameras\":[{\"id\":\"cam1\",\"name\":\"Тест камера\",\"enabled\":1}]}");
            if(p.equals("/api/public/play"))return json("{\"url\":\"/media/tv\",\"format\":\"mpegts\"}");
            if(p.equals("/api/public/camera-play"))return json("{\"url\":\"/media/camera\",\"format\":\"hls\"}");
            if(p.startsWith("/media/")){
                if(!String.valueOf(r.getHeader("Cookie")).contains("aston_public_sid=fixture"))return new MockResponse().setResponseCode(401);
                cookieSeen=true;
                if(p.equals("/media/camera"))return new MockResponse().addHeader("Content-Type","application/vnd.apple.mpegurl").setBody("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:30\n#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:30.0,\nsegment\n#EXT-X-ENDLIST\n");
                return new MockResponse().addHeader("Content-Type","video/mp2t").setBody(new Buffer().write(transport));
            }return new MockResponse().setResponseCode(404);
        }});server.start(java.net.InetAddress.getByName("127.0.0.1"),0);
    }
    private MockResponse json(String value){return new MockResponse().addHeader("Content-Type","application/json").setBody(value);}
    @After public void cleanup()throws Exception {server.shutdown();}
    @Test public void actualFramesRotateAndCameraHls()throws Exception {
        Intent intent=new Intent(InstrumentationRegistry.getInstrumentation().getTargetContext(),MainActivity.class).putExtra("test_server","http://127.0.0.1:"+server.getPort()+"/");
        try(ActivityScenario<MainActivity> scenario=ActivityScenario.launch(intent)){
            scenario.onActivity(a->a.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));
            Thread.sleep(1500);
            CountDownLatch tvFrame=new CountDownLatch(1);
            scenario.onActivity(a->{a.player.addListener(new Player.Listener(){@Override public void onRenderedFirstFrame(){tvFrame.countDown();}});try{a.play(new JSONObject("{\"id\":\"one\",\"name\":\"Тест телевизия\"}"),false);}catch(Exception e){throw new AssertionError(e);}});
            assertTrue("MPEG-TS must render an actual frame",tvFrame.await(30,TimeUnit.SECONDS));assertTrue("Gateway cookie reaches media request",cookieSeen);
            scenario.onActivity(a->{assertTrue(a.video.getHeight()>a.getWindow().getDecorView().getHeight()*0.3);assertFalse(a.isFull());});shot("portrait");
            scenario.onActivity(a->a.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE));Thread.sleep(1800);
            scenario.onActivity(a->{assertTrue(a.isFull());assertTrue(a.video.getWidth()>a.video.getHeight());assertTrue(a.video.getHeight()>a.getWindow().getDecorView().getHeight()*0.85);assertTrue(a.player.isPlaying());});shot("landscape");
            CountDownLatch cameraFrame=new CountDownLatch(1);
            scenario.onActivity(a->{a.player.addListener(new Player.Listener(){@Override public void onRenderedFirstFrame(){cameraFrame.countDown();}});try{a.play(new JSONObject("{\"id\":\"cam1\",\"name\":\"Тест камера\",\"enabled\":1}"),true);}catch(Exception e){throw new AssertionError(e);}});
            assertTrue("Camera HLS must render an actual frame",cameraFrame.await(30,TimeUnit.SECONDS));shot("camera-hls");
            scenario.onActivity(a->a.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));Thread.sleep(1500);
            scenario.onActivity(a->{assertFalse(a.isFull());assertTrue(a.player.isPlaying());});shot("portrait-return");
        }
    }
    private void shot(String name)throws Exception {Bitmap bitmap=InstrumentationRegistry.getInstrumentation().getUiAutomation().takeScreenshot();File dir=new File(InstrumentationRegistry.getInstrumentation().getTargetContext().getFilesDir(),"screenshots");dir.mkdirs();try(FileOutputStream out=new FileOutputStream(new File(dir,name+".png"))){bitmap.compress(Bitmap.CompressFormat.PNG,100,out);}}
}

package eu.astonserver.astontv.android;
import android.webkit.CookieManager;
import org.json.JSONObject;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class GatewayClient {
    static final String LOCAL="http://10.10.10.179:8424/", REMOTE="https://tv.astonserver.eu/";
    static final class Failure extends IOException {
        final int status;
        Failure(int status,String message){super(message);this.status=status;}
    }
    final String base;
    GatewayClient(String base){this.base=base;}
    JSONObject request(String path,JSONObject body) throws Exception {
        URL url=new URL(new URL(base),path);
        HttpURLConnection c=(HttpURLConnection)url.openConnection();
        c.setConnectTimeout(10000);c.setReadTimeout(30000);c.setInstanceFollowRedirects(false);
        String cookie=CookieManager.getInstance().getCookie(base);
        if(cookie!=null)c.setRequestProperty("Cookie",cookie);
        c.setRequestProperty("Accept","application/json");
        try {
            if(body!=null){c.setRequestMethod("POST");c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json");try(OutputStream out=c.getOutputStream()){out.write(body.toString().getBytes(StandardCharsets.UTF_8));}}
            int status=c.getResponseCode();
            for(Map.Entry<String,List<String>> h:c.getHeaderFields().entrySet())if("Set-Cookie".equalsIgnoreCase(h.getKey()))for(String v:h.getValue())CookieManager.getInstance().setCookie(base,v);
            CookieManager.getInstance().flush();
            if(status==401)throw new Failure(status,"Нужно е сдвояване с нов 8-цифрен код.");
            if(status<200||status>=300)throw new Failure(status,"Сървърът върна грешка "+status);
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();
            try(InputStream in=c.getInputStream()){byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1){if(bytes.size()+n>4*1024*1024)throw new IOException("Прекалено голям отговор");bytes.write(b,0,n);}}
            return new JSONObject(bytes.toString("UTF-8"));
        } finally {c.disconnect();}
    }
    String mediaUrl(String value) throws Exception {
        URI origin=new URI(base),url=origin.resolve(value);
        if(!Objects.equals(origin.getScheme(),url.getScheme())||!Objects.equals(origin.getHost(),url.getHost())||origin.getPort()!=url.getPort()||url.getUserInfo()!=null)throw new IOException("Видео адресът не е от избрания Gateway");
        return url.toString();
    }
    static boolean enabled(Object value){return Boolean.TRUE.equals(value)||"true".equalsIgnoreCase(String.valueOf(value))||"1".equals(String.valueOf(value));}
}

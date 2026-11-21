#!/usr/bin/env python3
"""Aston TV Portal 3.0: limited viewer-only proxy. Python standard library."""
import base64
import hmac
import hashlib
import json
import os
import tempfile
import re
import secrets
import threading
import time
import mimetypes
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlencode, urljoin, urlsplit, parse_qs, quote
from urllib.request import Request, build_opener, HTTPRedirectHandler
from urllib.error import HTTPError, URLError

ROOT = Path(__file__).resolve().parent
CORE = os.environ.get('ASTON_CORE_URL','http://10.10.10.179:8414').rstrip('/')
ALLOWED_ORIGINS = frozenset(x.rstrip('/') for x in os.environ.get('ASTON_ALLOWED_MEDIA_ORIGINS','http://10.10.10.179:8409').split(',') if x.strip())
KEY = os.environ.get('ASTON_PUBLIC_SIGNING_KEY','').encode()
HOST = os.environ.get('ASTON_PUBLIC_HOST','tv.astonserver.eu').lower()
PORT = int(os.environ.get('ASTON_PUBLIC_PORT','8416'))
if len(KEY)<48: raise RuntimeError('ASTON_PUBLIC_SIGNING_KEY needs at least 48 random characters')
if not CORE.startswith('http://10.10.10.'):
    raise RuntimeError('Core URL must be trusted private LAN HTTP URL')
if not ALLOWED_ORIGINS: raise RuntimeError('No allowed media origins')

lock = threading.RLock()
SESSION_FILE = Path(os.environ.get('ASTON_PUBLIC_SESSION_FILE',str(ROOT/'gateway_sessions.json')))
sessions = {} # random sid -> {device token, expiry}; persisted across Gateway restarts
SESSION_LIFETIME = 10*365*86400 # Remember a paired device; revocation is still checked with Core.
media = {} # opaque random id -> {trusted upstream URL, expiry, scope}
attempts = {}
limits = threading.BoundedSemaphore(10)
last_cleanup = 0

def load_sessions():
    try:
        with SESSION_FILE.open('r',encoding='utf-8') as f:
            data=json.load(f)
        now=time.time()
        return {sid:item for sid,item in data.items()
                if re.fullmatch(r'[A-Za-z0-9_-]{20,100}',sid)
                and isinstance(item,dict) and isinstance(item.get('token'),str)
                and len(item['token'])>=32 and item.get('exp',0)>now}
    except FileNotFoundError:return {}
    except (OSError,ValueError,TypeError):
        print('gateway: saved public sessions could not be loaded',flush=True)
        return {}

def save_sessions_locked():
    SESSION_FILE.parent.mkdir(parents=True,exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix='.gateway-sessions-',dir=str(SESSION_FILE.parent))
    try:
        if hasattr(os,'fchmod'):os.fchmod(fd,0o600)
        with os.fdopen(fd,'w',encoding='utf-8') as f:
            json.dump(sessions,f,separators=(',',':'))
            f.flush();os.fsync(f.fileno())
        os.replace(tmp,SESSION_FILE)
        if hasattr(os,'chmod'):os.chmod(SESSION_FILE,0o600)
    except Exception:
        try:os.unlink(tmp)
        except OSError:pass
        raise

sessions.update(load_sessions())

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None
opener=build_opener(NoRedirect)

def safe_url(url, kind):
    try:
        p=urlsplit(url)
        origin=f'{p.scheme}://{p.netloc}'
        decoded=p.path
        # Block path traversal / encoded separators and arbitrary internal APIs.
        from urllib.parse import unquote
        segments=unquote(decoded).split('/')
        if p.username or p.password or p.fragment or any(x in ('..','.') for x in segments):return False
        if p.scheme not in ('http','https'):return False
        if kind=='live':
            return origin in ALLOWED_ORIGINS and (p.path.startswith('/iptv/') or bool(re.fullmatch(r'/channel/[A-Za-z0-9_.-]+(?:\.m3u8)?',p.path)) or bool(re.fullmatch(r'/session/[A-Za-z0-9_./-]+',p.path)))
        if kind=='core':
            return origin==CORE and bool(re.fullmatch(r'/api/v2/(?:cameras/cam[1-8]/(?:hls|mp4|segment)|vod/media/[A-Za-z0-9_-]+)',p.path))
    except (ValueError,TypeError):pass
    return False

def live_mode(url):
    """Classify by known URL shape; unknown legacy streams default to MPEG-TS."""
    path=urlsplit(url).path.lower()
    if path.endswith(('.m3u8','.m3u')):return 'hls'
    return 'mpegts'

def upstream(url, method='GET', body=None, token=None, range_header=None, timeout=15):
    headers={'User-Agent':'AstonPublicGateway/0.1','Accept-Encoding':'identity'}
    if token:headers['X-Aston-Device']=token
    if body is not None:headers['Content-Type']='application/json'
    if range_header and re.fullmatch(r'bytes=\d*-\d*',range_header):headers['Range']=range_header
    return opener.open(Request(url,data=body,headers=headers,method=method),timeout=timeout)

def core_json(path,method='GET',payload=None,token=None):
    body=json.dumps(payload).encode() if payload is not None else None
    with upstream(CORE+path,method,body,token,timeout=10) as r:
        data=r.read(2_000_001)
        if len(data)>2_000_000: raise ValueError('Large Core response')
        return json.loads(data)

def public_camera(c):
    """Return only display-safe fields. Never serialize RTSP URLs, credentials or LAN paths."""
    ident = str(c.get('id', ''))
    if not re.fullmatch(r'cam[1-8]', ident):
        return None
    return {'id': ident, 'name': 'Камера ' + ident[-1],
            'enabled': bool(c.get('enabled')), 'sort_order': c.get('sort_order')}

def logo_origin_allowed(url):
    """Images are only fetched from explicit trusted LAN origins, never arbitrary M3U URLs."""
    try:
        p=urlsplit(url)
        origin=f'{p.scheme}://{p.netloc}'
        if p.scheme not in ('http', 'https') or p.username or p.password or p.fragment:
            return False
        if not p.path.startswith('/') or any(seg in ('.','..') for seg in p.path.split('/')):
            return False
        return origin == CORE or origin in ALLOWED_ORIGINS
    except (TypeError, ValueError):
        return False

# Exact filename map used *only* when Core has no usable logo.
# Never guess a logo for a different channel category.
LOGO_MAP = {
    'tv shows':'shows.png', 'tv show':'shows.png', 'предавания':'shows.png', 'shows':'shows.png',
    'horror movies':'horror.png', 'horror':'horror.png', 'ужаси':'horror.png', 'action':'action.png', 'комедия':'comedy.png', 'comedy':'comedy.png',
    'drama':'drama.png', 'драма':'drama.png', 'thriller':'thriller.png',
    'трилър':'thriller.png', 'fantasy':'fantasy.png', 'фентъзи':'fantasy.png',
    'romance':'romance.png', 'романтика':'romance.png', 'scifi':'scifi.png',
    'sci-fi':'scifi.png', 'animation':'animation.png', 'анимация':'animation.png',
    'house':'house.png', 'chalga':'chalga.png', 'чалга':'chalga.png',
    'music mix':'mix.png', 'bulgarian series':'bulgarian-series.png',
    'български сериали':'bulgarian-series.png', 'bulgarian movies':'bulgarian-movies.png',
    'български филми':'bulgarian-movies.png'
}
def logo_fallback(name):
    raw=str(name or '').lower()
    # Never substitute a MOVIES logo for a SERIES channel.
    if ('series' in raw or 'сериал' in raw) and not ('bulgarian series' in raw or 'български сериали' in raw):
        return None
    for phrase, file in sorted(LOGO_MAP.items(),key=lambda item:-len(item[0])):
        if phrase in raw:
            return file
    return None

def clean():
    global last_cleanup
    now=time.time()
    with lock:
        if last_cleanup + 60 > now: return
        last_cleanup = now
        sessions_changed=False
        for key,value in list(sessions.items()):
            if value['exp']<now:sessions.pop(key,None);sessions_changed=True
        for key,value in list(media.items()):
            if value['exp']<now:media.pop(key,None)
        # Cap in-memory ticket growth; the oldest tickets are evicted.
        while len(media)>4500:media.pop(next(iter(media)))
        while len(sessions)>1000:sessions.pop(next(iter(sessions)));sessions_changed=True
        if sessions_changed:save_sessions_locked()
        if len(attempts)>1500:attempts.clear()

def issue(url,kind,seconds=1800):
    clean()
    if not safe_url(url,kind):raise ValueError('Upstream address not permitted')
    ident=secrets.token_urlsafe(21)
    exp=int(time.time())+seconds
    with lock:media[ident]={'url':url,'kind':kind,'exp':exp}
    sig=hmac.new(KEY,f'{ident}:{exp}'.encode(),hashlib.sha256).hexdigest()
    return f'/media/{ident}?exp={exp}&sig={sig}'

def verify(ident,query):
    try:
        exp=int(query.get('exp',['0'])[0]);sig=query.get('sig',[''])[0]
    except (ValueError,TypeError):return None
    if exp < time.time() or exp>time.time()+3601 or len(sig)!=64:return None
    expected=hmac.new(KEY,f'{ident}:{exp}'.encode(),hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected,sig):return None
    with lock:
        item=media.get(ident)
        return item if item and item['exp']==exp else None

def rewrite_playlist(raw,base,kind):
    try:text=raw.decode('utf-8-sig')
    except UnicodeDecodeError:raise ValueError('Unsupported playlist encoding')
    if not text.lstrip().startswith('#EXTM3U'):raise ValueError('Not HLS')
    if len(text)>2_000_000:raise ValueError('HLS too large')
    def linked(value):
        target=urljoin(base,value)
        if not safe_url(target,kind):raise ValueError('HLS points to disallowed origin/path')
        return issue(target,kind)
    out=[]
    for line in text.splitlines():
        if line.startswith('#'):
            # Rewrite init files, key URIs, and nested variant playlists.
            line=re.sub(r'URI="([^"]+)"',lambda m:'URI="'+linked(m.group(1))+'"',line)
            out.append(line)
        elif line.strip():out.append(linked(line.strip()))
        else:out.append(line)
    return ('\n'.join(out)+'\n').encode('utf-8')

class Handler(BaseHTTPRequestHandler):
    protocol_version='HTTP/1.0'
    server_version='AstonPortal/3.0'
    def log_message(self,fmt,*args):
        # Never log URI query: signed media links are capabilities.
        print(f'gateway {self.client_address[0]} {self.command} {urlsplit(self.path).path}',flush=True)
    def headers_common(self,code,typ='application/json; charset=utf-8',length=None,extra=None):
        self.send_response(code)
        if 200<=code<300 and getattr(self,'authenticated_sid',None):
            local=self.headers.get('Host','').split(':')[0] in ('10.10.10.179','127.0.0.1','localhost')
            flags='HttpOnly; SameSite=Lax' if local else 'HttpOnly; Secure; SameSite=Strict'
            self.send_header('Set-Cookie',f'aston_public_sid={self.authenticated_sid}; Path=/; Max-Age={SESSION_LIFETIME}; {flags}')
        self.send_header('Content-Type',typ)
        self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Referrer-Policy','no-referrer')
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Frame-Options','DENY')
        self.send_header('Content-Security-Policy',"default-src 'self'; script-src 'self' https://cdn.jsdelivr.net; style-src 'self'; img-src 'self' data:; media-src 'self' blob:; worker-src 'self' blob:; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'")
        if length is not None:self.send_header('Content-Length',str(length))
        for k,v in (extra or {}).items():self.send_header(k,v)
        self.end_headers()
    def respond(self,code,obj):
        body=json.dumps(obj,ensure_ascii=False).encode()
        self.headers_common(code,length=len(body))
        if self.command!='HEAD':self.wfile.write(body)
    def fail(self,code,msg):self.respond(code,{'error':msg})
    def part(self):
        from urllib.parse import urlsplit
        p=urlsplit(self.path)
        return p.path,parse_qs(p.query)
    def read_json(self):
        size=self.headers.get('Content-Length','')
        if not size.isdigit() or int(size)>16_384:raise ValueError('Invalid request size')
        return json.loads(self.rfile.read(int(size)))
    def auth(self):
        token=self.headers.get('X-Aston-Device','')
        if token and len(token)<160:
            try:
                person=core_json('/api/v2/devices/me',token=token)
                return token,person.get('name','Устройство')
            except Exception:return None
        cookie=self.headers.get('Cookie','')
        m=re.search(r'(?:^|;\s*)aston_public_sid=([A-Za-z0-9_-]{20,100})(?:;|$)',cookie)
        if not m:return None
        with lock:item=sessions.get(m.group(1))
        if not item or item['exp']<time.time():return None
        # Recheck device revocation at most every 30 s.
        if item.get('checked',0)+30<time.time():
            try:person=core_json('/api/v2/devices/me',token=item['token'])
            except HTTPError as error:
                if error.code not in (401,403):raise ConnectionError('Core unavailable') from error
                with lock:
                    sessions.pop(m.group(1),None);save_sessions_locked()
                return None
            except Exception as error:
                raise ConnectionError('Core unavailable') from error
            with lock:
                item['checked']=time.time();item['name']=person.get('name','Устройство')
                item['exp']=time.time()+SESSION_LIFETIME
                save_sessions_locked()
        self.authenticated_sid=m.group(1)
        return item['token'],item.get('name','Устройство')
    def must_auth(self):
        try:user=self.auth()
        except ConnectionError:
            self.fail(503,'Core временно не е достъпен. Сдвояването е запазено.')
            return None
        if not user:self.fail(401,'Сдвояване с Aston Studio е необходимо')
        return user
    def origin_check(self):
        # Browser POSTs must originate from same public domain; CLI without Origin permitted.
        origin=self.headers.get('Origin')
        if not origin or origin==f'https://{HOST}':return True
        # Full-page local fallback uses a private-LAN origin (never expose this to the public web).
        host=self.headers.get('Host','').lower()
        return (host in ('10.10.10.179:8416','10.10.10.179:8424') and origin=='http://'+host) or (host=='10.10.10.179' and origin=='http://10.10.10.179')
    def request_guard(self):
        host=self.headers.get('Host','').lower().split(':')[0]
        if host not in (HOST,'10.10.10.179','127.0.0.1','localhost'):
            self.fail(421,'Unknown host');return False
        return True
    def do_HEAD(self):self.do_GET()
    def do_GET(self):
        if not self.request_guard():return
        path,q=self.part()
        if path=='/healthz':return self.respond(200,{'ok':True,'version':'4.1.0','ready':True})
        if path=='/health/pixel.gif':
            # 1x1 GIF, usable for cross-origin reachability probes from packaged clients.
            pixel=base64.b64decode('R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==')
            self.headers_common(200,'image/gif',len(pixel),{'Access-Control-Allow-Origin':'*'})
            if self.command!='HEAD':self.wfile.write(pixel)
            return
        if re.fullmatch(r'/logos/[a-z0-9-]+\.png',path):
            f=ROOT / path.lstrip('/')
            if not f.is_file():return self.fail(404,'Logo not found')
            raw=f.read_bytes()
            self.headers_common(200,'image/png',len(raw),{'Cache-Control':'public, max-age=86400'})
            if self.command!='HEAD':self.wfile.write(raw)
            return
        if path in ('/','/index.html','/app.js','/style.css'):
            name={'/':'index.html','/index.html':'index.html','/app.js':'app.js','/style.css':'style.css'}[path]
            typ={'index.html':'text/html; charset=utf-8','app.js':'application/javascript; charset=utf-8','style.css':'text/css; charset=utf-8'}[name]
            body=(ROOT/name).read_bytes()
            self.headers_common(200,typ,len(body))
            if self.command!='HEAD':self.wfile.write(body)
            return
        if path=='/api/public/me':
            user=self.must_auth()
            if user:return self.respond(200,{'ok':True,'name':user[1]})
            return
        if path=='/api/public/diagnostic':
            user=self.must_auth()
            if not user:return
            result={'gateway_version':'4.0.0','core':'unavailable','channels':None,'unsupported_streams':None,'cameras':None,'cameras_enabled':None}
            try:
                health=core_json('/api/v2/health')
                result['core']='online' if health.get('version') else 'unavailable'
            except Exception:pass
            try:
                records=core_json('/api/v2/channels').get('channels',[])
                result['channels']=len(records)
                result['unsupported_streams']=sum(1 for c in records if not safe_url(c.get('stream',''),'live'))
                result['hls_candidates']=sum(1 for c in records if live_mode(c.get('stream',''))=='hls')
                result['mpegts_candidates']=sum(1 for c in records if live_mode(c.get('stream',''))=='mpegts')
            except Exception:pass
            try:
                cams=core_json('/api/v2/cameras',token=user[0]).get('cameras',[])
                result['cameras']=len(cams)
                result['cameras_enabled']=sum(1 for c in cams if str(c.get('enabled','')).lower() in ('1','true'))
            except Exception:pass
            return self.respond(200,result)
        if path=='/api/public/channels':
            if not self.must_auth():return
            try:
                data=core_json('/api/v2/channels')
                channels=[]
                for x in data.get('channels',[]):
                    item={k:x.get(k) for k in ('id','number','name','group','now','next','programmes')}
                    item['logo_url']='/api/public/logo/'+hashlib.sha256(x['id'].encode()).hexdigest()[:24]
                    channels.append(item)
                return self.respond(200,{'channels':channels,'updated':data.get('updated')})
            except Exception:return self.fail(502,'Core channels unavailable')
        if path=='/api/public/cameras':
            user=self.must_auth()
            if not user:return
            try:
                data=core_json('/api/v2/cameras',token=user[0]);cams=data.get('cameras',[])
                return self.respond(200,{'cameras':[y for x in cams if (y:=public_camera(x)) is not None]})
            except Exception:return self.fail(502,'Camera list unavailable')
        if path=='/api/public/search':
            user=self.must_auth()
            if not user:return
            term=q.get('q',[''])[0][:90]
            try:return self.respond(200,core_json('/api/v2/search?'+urlencode({'q':term}),token=user[0]))
            except Exception:return self.fail(502,'Search unavailable')
        if re.fullmatch(r'/api/public/thumb/cam[1-8]',path):
            user=self.must_auth()
            if not user:return
            ident=path.rsplit('/',1)[-1]
            try:
                with upstream(CORE+f'/api/v2/cameras/{ident}/thumbnail',token=user[0],timeout=18) as response:
                    raw=response.read(1_500_001)
                if len(raw)>1_500_000 or not raw.startswith(b'\xff\xd8'):raise ValueError()
                self.headers_common(200,'image/jpeg',len(raw))
                if self.command!='HEAD':self.wfile.write(raw)
            except Exception:return self.fail(503,'Camera image unavailable')
            return
        if re.fullmatch(r'/api/public/logo/[A-Za-z0-9_-]{1,160}',path):
            if not self.must_auth():return
            cid=path.rsplit('/',1)[-1]
            try:
                channels=core_json('/api/v2/channels').get('channels',[])
                ch=next((x for x in channels if hashlib.sha256(x['id'].encode()).hexdigest()[:24]==cid),None)
                if not ch:raise ValueError()
                url=ch.get('logo','') or ''
                if url.startswith('/assets/logo/') and re.fullmatch(r'/assets/logo/[0-9a-f]{32}\.png',url):
                    target=CORE+url
                elif logo_origin_allowed(url):
                    target=url
                else:
                    target=None
                raw=None
                if target:
                    try:
                        with upstream(target,timeout=8) as r:
                            candidate=r.read(1_000_001)
                        if len(candidate)<=1_000_000 and candidate.startswith(b'\x89PNG\r\n\x1a\n'):
                            raw=candidate
                    except Exception:
                        pass
                if raw is None:
                    fallback=logo_fallback(ch.get('name'))
                    if not fallback:raise ValueError()
                    raw=(ROOT/'logos'/fallback).read_bytes()
                self.headers_common(200,'image/png',len(raw))
                if self.command!='HEAD':self.wfile.write(raw)
            except Exception:self.fail(404,'No logo')
            return
        if path.startswith('/media/'):
            ident=path.split('/')[-1]
            if not re.fullmatch(r'[A-Za-z0-9_-]{20,60}',ident):return self.fail(404,'Not found')
            ticket=verify(ident,q)
            if not ticket:return self.fail(403,'Media link expired or invalid')
            return self.stream(ticket)
        self.fail(404,'Not found')
    def stream(self,ticket):
        if not limits.acquire(blocking=False):return self.fail(503,'Stream capacity reached')
        try:
            if not safe_url(ticket['url'],ticket['kind']):return self.fail(403,'Source denied')
            r=upstream(ticket['url'],range_header=self.headers.get('Range'),timeout=25)
            with r:
                typ=r.headers.get('Content-Type','application/octet-stream').split(';')[0].lower()
                final=r.geturl()
                if final!=ticket['url']:return self.fail(502,'Redirect blocked')
                likely_hls=(urlsplit(ticket['url']).path.endswith('.m3u8') or typ in ('application/vnd.apple.mpegurl','application/x-mpegurl','audio/mpegurl'))
                if likely_hls:
                    raw=r.read(2_000_001)
                    if len(raw)>2_000_000:return self.fail(502,'Playlist too large')
                    try:data=rewrite_playlist(raw,ticket['url'],ticket['kind'])
                    except ValueError:return self.fail(502,'Playlist contains disallowed source')
                    self.headers_common(200,'application/vnd.apple.mpegurl',len(data))
                    if self.command!='HEAD':self.wfile.write(data)
                    return
                code=r.status
                extra={}
                for k in ('Content-Range','Accept-Ranges'):
                    if r.headers.get(k):extra[k]=r.headers[k]
                length=r.headers.get('Content-Length')
                self.headers_common(code,typ,int(length) if length and length.isdigit() else None,extra)
                if self.command!='HEAD':
                    while True:
                        chunk=r.read(64*1024)
                        if not chunk:break
                        self.wfile.write(chunk)
        except (BrokenPipeError,ConnectionResetError):pass
        except HTTPError as e:
            try:self.fail(502,'Media source returned HTTP '+str(e.code))
            except Exception:pass
        except (TimeoutError,URLError,OSError,ValueError):
            try:self.fail(502,'Media source unavailable')
            except Exception:pass
        finally:limits.release()
    def do_POST(self):
        if not self.request_guard():return
        path,_=self.part()
        if not self.origin_check():return self.fail(403,'Cross-site request denied')
        try:payload=self.read_json()
        except (ValueError,json.JSONDecodeError):return self.fail(400,'Invalid JSON')
        if path=='/api/public/pair':
            clean()
            code=str(payload.get('code',''))
            if not re.fullmatch(r'\d{8}',code):return self.fail(400,'Enter 8 digit pairing code')
            ip=self.client_address[0]
            now=time.time()
            with lock:
                hits=[x for x in attempts.get(ip,[]) if now-x<60]
                if len(hits)>=8:return self.fail(429,'Too many pairing attempts')
                hits.append(now);attempts[ip]=hits
            try:
                result=core_json('/api/v2/pair','POST',{'code':code,'name':'Aston Public Web'})
                token=result.get('token','')
                if len(token)<32:raise ValueError()
                sid=secrets.token_urlsafe(36)
                with lock:
                    sessions[sid]={'token':token,'name':'Aston Public Web','exp':now+SESSION_LIFETIME,'checked':now}
                    save_sessions_locked()
                self.send_response(200)
                data=b'{"ok":true}'
                self.send_header('Content-Type','application/json')
                self.send_header('Content-Length',str(len(data)))
                self.send_header('Cache-Control','no-store')
                local_client=self.headers.get('Host','').split(':')[0] in ('10.10.10.179','127.0.0.1','localhost')
                cookie_flags='HttpOnly; SameSite=Lax' if local_client else 'HttpOnly; Secure; SameSite=Strict'
                self.send_header('Set-Cookie',f'aston_public_sid={sid}; Path=/; Max-Age={SESSION_LIFETIME}; {cookie_flags}')
                self.send_header('X-Content-Type-Options','nosniff')
                self.end_headers();self.wfile.write(data)
            except HTTPError:return self.fail(401,'Invalid or expired pairing code')
            except Exception:return self.fail(502,'Pairing unavailable')
            return
        if path=='/api/public/logout':
            cookie=self.headers.get('Cookie','');m=re.search(r'aston_public_sid=([A-Za-z0-9_-]+)',cookie)
            if m:
                with lock:
                    sessions.pop(m.group(1),None);save_sessions_locked()
            body=b'{"ok":true}'
            self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)))
            self.send_header('Set-Cookie','aston_public_sid=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Strict');self.end_headers();self.wfile.write(body)
            return
        user=self.must_auth()
        if not user:return
        if path=='/api/public/play':
            cid=payload.get('channel_id','')
            force=payload.get('format','auto')
            if force not in ('auto','hls','mpegts'):return self.fail(400,'Invalid playback format')
            try:
                rows=core_json('/api/v2/channels').get('channels',[])
                ch=next((x for x in rows if x.get('id')==cid),None)
                if not ch: return self.fail(404,'Channel not found')
                url=ch.get('stream','')
                if not safe_url(url,'live'):return self.fail(409,'Unsupported stream address (not in allowlist)')
                mode=live_mode(url) if force=='auto' else force
                return self.respond(200,{'url':issue(url,'live'),'name':ch.get('name'),'format':mode,'detected_by':'url' if force=='auto' else 'manual'})
            except Exception:return self.fail(502,'Channel unavailable')
        if path=='/api/public/camera-play':
            ident=payload.get('camera','');fmt=payload.get('format','hls')
            if not re.fullmatch(r'cam[1-8]',str(ident)) or fmt not in ('hls','mp4'):return self.fail(400,'Invalid camera or format')
            try:
                cameras=core_json('/api/v2/cameras',token=user[0]).get('cameras',[])
                if not any(x['id']==ident and str(x.get('enabled','')).lower() in ('1','true') for x in cameras):return self.fail(404,'Camera disabled')
                url=CORE+f'/api/v2/cameras/{ident}/{fmt}?'+urlencode({'access':user[0]})
                return self.respond(200,{'url':issue(url,'core'),'name':ident})
            except Exception:return self.fail(502,'Camera unavailable')
        if path in ('/api/public/vod/resolve','/api/public/vod/resume','/api/public/vod/progress'):
            tail=path.rsplit('/',1)[-1]
            if tail=='progress':
                try:return self.respond(200,core_json('/api/v2/vod/progress','POST',payload,token=user[0]))
                except Exception:return self.fail(502,'Progress unavailable')
            try:
                result=core_json('/api/v2/vod/'+tail,'POST',payload,token=user[0])
                url=result.get('url','')
                if not re.fullmatch(r'/api/v2/vod/media/[A-Za-z0-9_-]+',url):return self.fail(502,'Unexpected VOD address')
                result['url']=issue(CORE+url,'core',seconds=3600)
                return self.respond(200,result)
            except HTTPError as error:
                if error.code in (404,409):return self.fail(error.code,'Programme unavailable in Plex')
                if error.code in (401,403):return self.fail(401,'Device authorization required')
                return self.fail(503,'Plex temporarily unavailable')
            except Exception:return self.fail(502,'VOD unavailable')
        self.fail(404,'Not found')

def main():
    print('Aston gateway ready at port',PORT,flush=True)
    ThreadingHTTPServer(('0.0.0.0',PORT),Handler).serve_forever()

if __name__=='__main__':main()

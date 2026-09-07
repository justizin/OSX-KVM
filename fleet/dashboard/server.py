#!/usr/bin/env python3
"""Fleet dashboard server: serves the app + status, accepts pushes from workers.

GET  /                 -> index.html (from app dir)
GET  /status.json      -> current status (from DASH_DATA)
GET  /<id>.png         -> a VM's latest frame (from DASH_DATA)
PUT  /shot/<id>        -> body is a PNG; saved as <id>.png
POST /state/<id>       -> JSON {host,title,state,attention,sentence}; upserts entry
POST /remove/<id>      -> drop a VM (e.g. when it powers off)

Workers on any host push here (see publish.sh). No dependency on the coordinator
laptop -- this runs on the always-on server (og128x01).
"""
import json, os, threading, datetime, mimetypes
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
APP = os.path.dirname(os.path.abspath(__file__))
DATA = os.environ.get("DASH_DATA", "/data")
LOCK = threading.Lock()
ORDER = {"waiting":0,"installing":1,"booting":2,"ready":3,"done":4,"idle":5}
def sp(): return os.path.join(DATA, "status.json")
def load():
    try:
        with open(sp()) as f: return json.load(f)
    except Exception: return {"vms":[]}
def save(d):
    t = sp()+".tmp"
    with open(t,"w") as f: json.dump(d,f,indent=2)
    os.replace(t, sp())
class H(BaseHTTPRequestHandler):
    def _s(self, code, body=b"", ctype="application/octet-stream"):
        self.send_response(code); self.send_header("Content-Type",ctype)
        self.send_header("Content-Length",str(len(body)))
        self.send_header("Access-Control-Allow-Origin","*"); self.end_headers()
        if body: self.wfile.write(body)
    def do_GET(self):
        p = self.path.split("?")[0]
        if p in ("/","/index.html"):
            fp=os.path.join(APP,"index.html")
            return self._s(200, open(fp,"rb").read(), "text/html; charset=utf-8")
        if p=="/status.json":
            with LOCK: return self._s(200, json.dumps(load()).encode(), "application/json")
        if p.endswith(".png"):
            fp=os.path.join(DATA, os.path.basename(p))
            if os.path.isfile(fp): return self._s(200, open(fp,"rb").read(), "image/png")
            return self._s(404,b"no image")
        if p.startswith("/novnc/") and ".." not in p:
            fp=os.path.join(APP, p.lstrip("/"))
            if os.path.isfile(fp):
                ctype = "text/javascript" if fp.endswith(".js") else (mimetypes.guess_type(fp)[0] or "application/octet-stream")
                return self._s(200, open(fp,"rb").read(), ctype)
            return self._s(404,b"no file")
        return self._s(404,b"not found")
    def do_PUT(self):
        if self.path.startswith("/shot/"):
            vid=os.path.basename(self.path[6:]); n=int(self.headers.get("Content-Length",0))
            open(os.path.join(DATA,vid+".png"),"wb").write(self.rfile.read(n))
            return self._s(200,b"ok")
        return self._s(404,b"not found")
    def do_POST(self):
        if self.path.startswith("/state/"):
            vid=os.path.basename(self.path[7:]); n=int(self.headers.get("Content-Length",0))
            j=json.loads(self.rfile.read(n) or b"{}")
            now=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
            e={"id":vid,"host":j.get("host",""),"title":j.get("title",vid),
               "state":j.get("state","idle"),"attention":bool(j.get("attention",False)),
               "sentence":j.get("sentence",""),"img":vid+".png",
               "vnc":j.get("vnc",""),"vnc_native":j.get("vnc_native",""),"updated":now}
            with LOCK:
                d=load(); vms=[v for v in d.get("vms",[]) if v.get("id")!=vid]+[e]
                vms.sort(key=lambda v:(0 if v["attention"] else 1, ORDER.get(v["state"],9), v["id"]))
                d["vms"]=vms; d["updated"]=now; save(d)
            return self._s(200,b"ok")
        if self.path.startswith("/remove/"):
            vid=os.path.basename(self.path[8:])
            with LOCK:
                d=load(); d["vms"]=[v for v in d.get("vms",[]) if v.get("id")!=vid]; save(d)
            return self._s(200,b"ok")
        return self._s(404,b"not found")
    def log_message(self,*a): pass
if __name__=="__main__":
    os.makedirs(DATA, exist_ok=True)
    print(f"dashboard on :8090  app={APP} data={DATA}")
    ThreadingHTTPServer(("0.0.0.0",8090), H).serve_forever()

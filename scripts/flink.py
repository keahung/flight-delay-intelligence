#!/usr/bin/env python3
"""Submit a Flink SQL statement to Confluent Cloud and print results."""
import json,os,sys,time,urllib.request,base64,uuid
ORG=os.environ["CC_ORG_ID"]; ENV=os.environ["CC_ENV_ID"]; POOL=os.environ["CC_COMPUTE_POOL_ID"]
BASE=f"https://flink.us-east1.gcp.confluent.cloud/sql/v1/organizations/{ORG}/environments/{ENV}"
KEY=os.environ["CONFLUENT_CLOUD_API_KEY"]
SEC=os.environ["CONFLUENT_CLOUD_API_SECRET"]
AUTH="Basic "+base64.b64encode(f"{KEY}:{SEC}".encode()).decode()

def req(method,url,body=None):
    r=urllib.request.Request(url,method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization":AUTH,"Content-Type":"application/json"})
    try:
        with urllib.request.urlopen(r,timeout=90) as f: return json.loads(f.read().decode() or "{}")
    except urllib.error.HTTPError as e: return json.loads(e.read().decode() or "{}")

def run(sql,name=None,wait=True,max_rows=25,timeout=180):
    name=name or "s-"+uuid.uuid4().hex[:12]
    d=req("POST",f"{BASE}/statements",{"name":name,"spec":{
        "statement":sql,"compute_pool_id":POOL,
        "properties":{"sql.current-catalog":"default","sql.current-database":"cluster_0",
                      "sql.tables.scan.startup.mode":"earliest-offset",
                      "sql.tables.scan.idle-timeout":"60 s"}}})
    if "errors" in d:
        print("SUBMIT ERROR:",json.dumps(d["errors"])[:800]); return None
    t0=time.time(); phase=None
    while time.time()-t0<timeout:
        s=req("GET",f"{BASE}/statements/{name}"); st=s.get("status",{}); phase=st.get("phase")
        if phase in ("RUNNING","COMPLETED","FAILED","STOPPED"): 
            if phase=="FAILED": print("FAILED:",st.get("detail","")[:900]); return None
            break
        time.sleep(3)
    print(f"[{name}] phase={phase}")
    if not wait: return name
    rows=[]; url=f"{BASE}/statements/{name}/results"
    t0=time.time()
    while len(rows)<max_rows and time.time()-t0<timeout:
        r=req("GET",url)
        if "errors" in r: print("RESULT ERROR:",json.dumps(r["errors"])[:500]); break
        data=(r.get("results") or {}).get("data") or []
        for it in data:
            if it.get("op") in (0,None): rows.append(it.get("row"))
        nxt=(r.get("metadata") or {}).get("next")
        if not nxt: break
        url=nxt
        if not data: time.sleep(2)
    for row in rows[:max_rows]: print("  ",row)
    print(f"  ({len(rows)} rows)")
    return name

if __name__=="__main__":
    sql=sys.argv[1] if len(sys.argv)>1 else sys.stdin.read()
    run(sql, name=(sys.argv[2] if len(sys.argv)>2 else None))

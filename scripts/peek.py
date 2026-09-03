# /// script
# dependencies = ["confluent-kafka"]
# ///
import json,sys
from confluent_kafka import Consumer, TopicPartition
kv=dict(l.strip().split('=',1) for l in open('kafka-key.env') if '=' in l)
c=Consumer({'bootstrap.servers':'pkc-619z3.us-east1.gcp.confluent.cloud:9092',
 'security.protocol':'SASL_SSL','sasl.mechanisms':'PLAIN',
 'sasl.username':kv['KAFKA_API_KEY'],'sasl.password':kv['KAFKA_API_SECRET'],
 'group.id':'peek-'+str(__import__('time').time()),'auto.offset.reset':'earliest'})
for topic in sys.argv[1:]:
    tp=TopicPartition(topic,0)
    lo,hi=c.get_watermark_offsets(tp,timeout=15)
    print(f"\n=== {topic}: offsets {lo}..{hi}  ({hi-lo} records) ===")
    if hi<=lo: print("  EMPTY"); continue
    c.assign([TopicPartition(topic,0,max(lo,hi-1))])
    m=c.poll(20)
    if m is None or m.error(): print("  no message:",m.error() if m else "timeout"); continue
    v=json.loads(m.value())
    print("  record type:",type(v).__name__)
    if isinstance(v,dict): print("  keys:",sorted(v.keys())[:18])
    print("  sample:",json.dumps(v)[:420])
c.close()

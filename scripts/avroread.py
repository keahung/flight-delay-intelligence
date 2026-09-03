# /// script
# dependencies = ["confluent-kafka[avro,schemaregistry]", "fastavro"]
# ///
import sys,time,json
from confluent_kafka import Consumer, TopicPartition
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroDeserializer
from confluent_kafka.serialization import SerializationContext, MessageField
kv=dict(l.strip().split('=',1) for l in open('kafka-key.env') if '=' in l)
sv=dict(l.strip().split('=',1) for l in open('sr-key.env') if '=' in l)
sr=SchemaRegistryClient({'url':'https://psrc-15ov57k.us-east1.gcp.confluent.cloud',
  'basic.auth.user.info':f"{sv['SR_API_KEY']}:{sv['SR_API_SECRET']}"})
topic=sys.argv[1]; want=int(sys.argv[2]) if len(sys.argv)>2 else 20
de=AvroDeserializer(sr)
c=Consumer({'bootstrap.servers':'pkc-619z3.us-east1.gcp.confluent.cloud:9092',
 'security.protocol':'SASL_SSL','sasl.mechanisms':'PLAIN','session.timeout.ms':45000,
 'sasl.username':kv['KAFKA_API_KEY'],'sasl.password':kv['KAFKA_API_SECRET'],
 'group.id':'av-'+str(time.time()),'auto.offset.reset':'earliest'})
md=c.list_topics(topic,timeout=20)
parts=list(md.topics[topic].partitions)
c.assign([TopicPartition(topic,p,0) for p in parts])
out=[];t0=time.time()
while len(out)<want and time.time()-t0<50:
    m=c.poll(3)
    if m is None: continue
    if m.error(): continue
    try: out.append(de(m.value(),SerializationContext(topic,MessageField.VALUE)))
    except Exception as e: out.append({"_decode_error":str(e)[:120]})
for r in out: print(json.dumps(r,default=str))
print(f"-- {len(out)} records from {topic}")
c.close()

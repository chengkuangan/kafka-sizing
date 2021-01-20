# AMQ Streams Sizing on OpenShift

### Draft and not updated properly yet!

# Configuration Being Used

1. Kafka v2.5
2. 

# Installing Kafka Cluster

Run the following command to install Kafka on OpenShift:

`oc apply -f ./Templates/kafka-persistent-1.yaml -n kafka-sizing`

Run the producer performance tester:

`oc run kafka-producer -ti --image=registry.redhat.io/amq7/amq-streams-kafka-26-rhel7:1.6.0 --rm=true --restart=Never -n kafka-sizing -- bin/kafka-producer-perf-test.sh  --topic kafka-sizing --throughput -1 --num-records 3000000 --record-size 1024 --producer-props acks=all bootstrap.servers=my-cluster-kafka-bootstrap:9092`

--topic kafka-sizing --throughput -1 --num-records 3000000 --record-size 1024 --producer-props acks=all bootstrap.servers=my-cluster-kafka-bootstrap:9092 \


oc run kafka-producer -ti --image=registry.redhat.io/amq7/amq-streams-kafka-26-rhel7:1.6.0 --rm=true --restart=Never -n kafka-sizing -- bin/kafka-producer-perf-test.sh  --topic kafka-sizing --throughput -1 --num-records 3000000 --record-size 1024 --producer-props acks=all bootstrap.servers=my-cluster-kafka-bootstrap:9092

### Producer Batch Size as variables

NUM_RECORDS=3000000
BATCH_SIZE=24576

oc run kafka-producer -ti --image=registry.redhat.io/amq7/amq-streams-kafka-26-rhel7:1.6.0 --rm=true --restart=Never -n kafka-sizing -- bin/kafka-producer-perf-test.sh  --topic kafka-sizing --throughput -1 --num-records $NUM_RECORDS --record-size 1024 --producer-props acks=1 batch.size=$BATCH_SIZE bootstrap.servers=my-cluster-kafka-bootstrap:9092

./kafka-topics.sh --describe --zookeeper my-cluster-zookeeper-client:2181 --topic kafka-testing




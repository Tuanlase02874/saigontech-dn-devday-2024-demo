import json 
from kafka import KafkaConsumer

if __name__ == '__main__':
    # Kafka Consumer 
    consumer = KafkaConsumer(
        'testkafka',
        bootstrap_servers='kafka:9092',
        auto_offset_reset='earliest',
        group_id='dnstudent',
    )
    print("Success start Kafka Consumer")
    for message in consumer:
        my_bytes_value = message.value
        my_json = my_bytes_value.decode('utf8').replace("'", '"')
        print(json.loads(my_json))

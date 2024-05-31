import time 
import json 
import random 
from datetime import datetime
from kafka import KafkaProducer


def generate_message(user ='user_id', model ='model_a'):
    current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    return f"{user} - {model} :  Wellcom DEVDAY DANANG 2024 at {current_time}"

# Messages will be serialized as JSON 
def serializer(message):
    return json.dumps(message).encode('utf-8')

def send_message(topic, message):
    # try:
    producer = KafkaProducer(bootstrap_servers=['kafka:9092'], value_serializer=serializer)
    producer.send(topic, value=message)
    producer.flush()
    return True
    # except Exception as e:
    #     print(f"Error sending message: {e}")
    #     return False

if __name__ == '__main__':

    # Infinite loop - runs until you kill the program
    while True:
        # Generate a message
        dummy_message = generate_message(user ='user_id', model ='model_a')
        
        # Send it to our 'messages' topic
        print(f'Producing message @ {datetime.now()} | Message = {str(dummy_message)}')
        send_message('testkafka', dummy_message) 
        
        # Sleep for a random number of seconds
        time_to_sleep = random.randint(1, 11)
        time.sleep(time_to_sleep)

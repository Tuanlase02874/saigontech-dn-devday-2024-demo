# saigontech-dn-devday-2024-demo


```
docker compose up -d

docker exec -it saigontech-dn-devday-2024-demo-triton-server-1 bash 
bash ./start-triton-server.sh  \
--models yolov9-c,yolov7 \
--model_mode eval \
--plugin efficientNMS \
--opt_batch_size 4 \
--max_batch_size 4 \
--instance_group 1

bash ./start-triton-server.sh  \
--models yolov9-c,yolov9-e,yolov7,yolov7x \
--model_mode infer \
--plugin efficientNMS \
--opt_batch_size 4 \
--max_batch_size 4 \
--instance_group 1

docker exec -it saigontech-dn-devday-2024-demo-triton_client-1 bash 
python3 client.py image --model yolov9-e data/dog.jpg


```
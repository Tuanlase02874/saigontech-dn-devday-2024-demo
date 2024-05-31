#!/bin/bash

tritonserver --trace-config triton,file=/app/trace.json \
  --trace-config triton,log-frequency=50 \
  --trace-config rate=100 \
  --trace-config level=TIMESTAMPS \
  --trace-config count=100  \
  --model-repository=/app/models \
  --disable-auto-complete-config \
  --model-control-mode=poll \
  --repository-poll-secs=30 \
  --log-verbose=0
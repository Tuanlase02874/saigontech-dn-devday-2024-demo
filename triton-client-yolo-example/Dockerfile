FROM python:3.9.6-slim-buster

WORKDIR /app

# set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# install system dependencies
RUN apt-get update \
    && apt-get -y install kafkacat\
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y libzmq3-dev && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install ffmpeg libsm6 libxext6  -y && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
RUN pip install opencv-python


# # install python dependencies
RUN pip install --upgrade pip 
COPY ./requirements.txt .
RUN pip install -r requirements.txt --no-cache-dir
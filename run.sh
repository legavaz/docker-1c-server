#!/bin/sh

docker run --name 1c-server \
  --net host \
  --detach \
  --volume ./usr1cv8:/home/usr1cv8 \
  --volume ./log:/var/log/1C \
  --volume /etc/localtime:/etc/localtime:ro \
  v83-1996/1c-server

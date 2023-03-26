bd:
	docker build --tag v83-1996/1c-server .

run:
	docker run --name 1c-server \
  --net bridge \
  --detach \
  --volume /home/usr1cv8 \
  --volume /var/log/1C \
  --volume /etc/localtime:/etc/localtime:ro \
  v83-1996/1c-server

del:
	docker rm 1c-server

stop:
	docker stop 1c-server


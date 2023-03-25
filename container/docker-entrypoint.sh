#!/bin/bash

service srv1cv83 start
exec top -b

# if [ "$1" = "ragent" ]; then
#   exec gosu usr1cv8 /opt/1C/v8.3/x86_64/8.3.20.1996/srv1cv83 start
# fi

# exec "$@"

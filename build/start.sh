#!/usr/bin/env bash

##
# Run a command or start supervisord
#
if [ $# -gt 0 ];then
    # If we passed a command, run it
    exec "$@"
else
    # Otherwise start supervisord
    /usr/bin/supervisord -c /etc/supervisord/supervisord.conf
fi
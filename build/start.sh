#!/usr/bin/env bash

set -x
##
# set zone info
#
if [[ $(cat /etc/timezone) != "$TZ" ]]; then
  ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
  dpkg-reconfigure -f noninteractive tzdata
fi
##
# Run a command or start supervisord
#

if [ $# -gt 0 ];then
    # If we passed a command, run it
    exec "$@"
else
    # Otherwise start supervisord
    /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
fi
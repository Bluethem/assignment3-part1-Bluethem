#!/bin/sh

DAEMON="aesdsocket"
DAEMON_PATH="/usr/bin/aesdsocket"
PIDFILE="/var/run/aesdsocket.pid"

case "$1" in
    start)
        echo "Starting $DAEMON"
        start-stop-daemon -S -n $DAEMON -a $DAEMON_PATH -p $PIDFILE -- -d
        ;;
    stop)
        echo "Stopping $DAEMON"
        start-stop-daemon -K -n $DAEMON -p $PIDFILE -s SIGTERM
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
esac

exit 0

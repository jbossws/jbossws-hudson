#!/bin/sh

PROGNAME=`basename $0`
DIRNAME=`dirname $0`
JBOSS_HOME="$1"
CMD="$2"
BINDADDR="$3"

export JBOSS_HOME
PIDFILE="$JBOSS_HOME/bin/jboss.pid"

if [ -f "$JBOSS_HOME/bin/run.sh" ]; then
   RUN_CMD="$DIRNAME/runjboss.sh -b $BINDADDR"
else
   RUN_CMD="$JBOSS_HOME/bin/standalone.sh -server-config standalone-preview.xml"
   export LAUNCH_JBOSS_IN_BACKGROUND="true"
   export JBOSS_PIDFILE=$PIDFILE
fi

#
# Helper to complain.
#
warn() {
   echo "$PROGNAME: $*"
}

case "$CMD" in
start)
    # This version of run.sh obtains the pid of the JVM and saves it as jboss.pid
    # It relies on bash specific features
    /bin/bash $RUN_CMD &
    ;;
stop)
    if [ -f "$PIDFILE" ]; then
       pid=`cat "$PIDFILE"`
       echo "kill pid: $pid"
       kill $pid
       if [ "$?" -eq 0 ]; then
         # process exists, wait for it to die, and force if not
         sleep 20
         kill -9 $pid &> /dev/null
       fi
       rm "$PIDFILE"
    else
       warn "No pid found!"
    fi
    ;;
restart)
    $0 stop
    $0 start
    ;;
*)
    echo "usage: $0 JBOSS_HOME (start|stop|restart|help)"
esac


#!/bin/sh

PROGNAME=`basename $0`
DIRNAME=`dirname $0`
JBOSS_HOME="$1"
CMD="$2"
BINDADDR="$3"

export JBOSS_HOME
PIDFILE="$JBOSS_HOME/bin/jboss.pid"

# Overwrite standalone.xml with standalone-preview.xml if available (AS 7.0.x)
if [ -f "$JBOSS_HOME/standalone/configuration/standalone-preview.xml" ]; then
   cp $JBOSS_HOME/standalone/configuration/standalone-preview.xml $JBOSS_HOME/standalone/configuration/standalone.xml
fi

# Overwrite standalone.xml with standalone-preview.xml if available (AS 7.1.x since https://github.com/jbossas/jboss-as/commit/641a75718909fbe04f80a15740ecb26d4889c66e )
if [ -f "$JBOSS_HOME/standalone/configuration/standalone-full.xml" ]; then
   cp $JBOSS_HOME/standalone/configuration/standalone-full.xml $JBOSS_HOME/standalone/configuration/standalone.xml
fi

if [ -f "$JBOSS_HOME/bin/run.sh" ]; then
   RUN_CMD="$DIRNAME/runjboss.sh -b $BINDADDR"
else
   RUN_CMD="$JBOSS_HOME/bin/standalone.sh"
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


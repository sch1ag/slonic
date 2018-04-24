#!/bin/sh

PATH=/bin:/usr/bin:/sbin:/usr/sbin:${PATH}

#check for perl
which perl > /dev/null 2>&1 || exit 0

#check for SLONIC_HOME var (see /etc/default/slonic)
if [ -z "${SLONIC_HOME}" ]; then
    echo <<EOF "Env var SLONIC_HOME must be defined.
Normally $0 script started by init sybsystem (for example /etc/init.d/slonic)
which export SLONIC_HOME somehow (for example by sourcing /etc/default/slonic file)"
EOF
    exit 1
fi

. ${SLONIC_HOME}/etc/slonic.env

#check that needed env vars are defined (see ${SLONIC_HOME}/etc/slonic.env)
if [ -z "${SLONIC_ETC}" -o -z "${SLONIC_VAR}" -o -z "${SLONIC_CHIEF_PIDFILE}" -o -z "${SLONIC_STARTER_LOGFILE}" ] ; then
    echo <<EOF "Env vars SLONIC_ETC, SLONIC_VAR, SLONIC_CHIEF_PIDFILE, SLONIC_STARTER_LOGFILE must be defined.
Normally they are defined in ${SLONIC_HOME}/etc/slonic.env file."
EOF
    exit 1
fi

#check for running slonic.chief.pl process
SLONIC_CHIEF_PID=""
if [ -f "${SLONIC_CHIEF_PIDFILE}" ]; then
    SLONIC_CHIEF_PID_FROM_FILE=`cat ${SLONIC_CHIEF_PIDFILE}`
    if ps -o args -p ${SLONIC_CHIEF_PID_FROM_FILE} | grep slonic.chief.pl > /dev/null 2>&1 ; then
        SLONIC_CHIEF_PID=${SLONIC_CHIEF_PID_FROM_FILE}
    fi
fi

case "$1" in
  start)
        if [ -z "${SLONIC_CHIEF_PID}" ]; then
            #set default tags as env vars
            SLONIC_TAG_hostid=`hostid`
            export SLONIC_TAG_hostid

            #check for writable log file
            touch ${SLONIC_STARTER_LOGFILE}
            chmod +w ${SLONIC_STARTER_LOGFILE}

            #limit memory usage to 100MiB by one process 
            ulimit -v 102400
            ulimit -Hv 102400

            #run slonic starter that will start chief daemon itself
            perl ${SLONIC_HOME}/bin/slonic.starter.pl > ${SLONIC_STARTER_LOGFILE} 2>&1
        fi
        ;;
  stop)
        if [ -n "${SLONIC_CHIEF_PID}" ]; then
            kill -- -${SLONIC_CHIEF_PID}
        fi
        ;;
  status)
        if [ -n "${SLONIC_CHIEF_PID}" ]; then
            echo "Slonic chief is running with pid ${SLONIC_CHIEF_PID}."
        else
            echo "Looks like Slonic is not running."
        fi
        exit 0
        ;;
  *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
esac

exit 0


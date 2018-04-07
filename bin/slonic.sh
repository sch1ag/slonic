#!/bin/sh

PATH=/bin:/usr/bin:/sbin:/usr/sbin:${PATH}

#check for perl
which perl > /dev/null 2>&1 || exit 0

#check that needed env vars are defined (see /etc/default/slonic)
if [ -z "${SLONIC_HOME}" -o -z "${SLONIC_ETC}" -o -z "${SLONIC_VAR}" -o -z "${SLONIC_CHIEF_PIDFILE}" -o -z "${SLONIC_LOGFILE}" ] ; then

    echo <<EOF "Env vars SLONIC_HOME, SLONIC_ETC, SLONIC_VAR, SLONIC_CHIEF_PIDFILE, SLONIC_LOGFILE must be defined.
Normally $0 script started by init sybsystem from /etc/init.d/slonic which sources /etc/default/slonic file where vars are defined."
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
            touch ${SLONIC_LOGFILE}
            chmod +w ${SLONIC_LOGFILE}

            #limit memory usage to 100MiB by one process 
            ulimit -v 102400
            ulimit -Hv 102400

            #run slonic chief itself
            perl ${SLONIC_HOME}/bin/slonic.chief.pl > ${SLONIC_LOGFILE} 2>&1
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


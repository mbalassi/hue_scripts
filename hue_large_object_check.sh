#!/bin/bash
#Looks for objects larger than 10mb

#parse command line arguments
parse_arguments()
{
  # Test that we're using compatible getopt version.
  getopt -T > /dev/null
  if [[ $? -ne 4 ]]; then
    echo "Incompatible getopt version."
    exit 1
  fi

  # Parse short and long option parameters.
  OVERRIDE=
  VERBOSE=
  SIZE=`expr 1024 \* 1024 \* 10`
  DESKTOP_DEBUG=false
  GETOPT=`getopt -n $0 -o o,s:,v,h \
      -l override,size:,verbose,help \
      -- "$@"`
  eval set -- "$GETOPT"
  while true;
  do
    case "$1" in
    -o|--override)
      OVERRIDE=true
      shift
      ;;
    -s|--size)
      SIZE=`expr $2 \* 1024`
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=true
      DESKTOP_DEBUG=true
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      usage
      exit 1
      ;;
    esac
  done

  #
}

usage()
{
cat << EOF
usage: $0 [options]

Find large objects

OPTIONS
   -s|--size 		   Search for objects greater than size k.
   -o|--override           Allow script to run as non-root, must set HUE_CONF_DIR manually before running
   -v|--verbose            Verbose logging, off by default
   -h|--help               Show this message.
EOF
}

debug()
{
   if [[ ! -z $VERBOSE ]]
   then
      echo "$1" >> ${LOG_FILE}
   fi
}

main()
{

  parse_arguments "$@"

  SCRIPT_DIR="$( cd -P "$( dirname "$0" )" && pwd )"
  PYTHONPATH=${SCRIPT_DIR}/lib:${PYTHONPATH}
  export SCRIPT_DIR PYTHONPATH

  #SET IMPORTANT ENV VARS
  if [ -d "/var/run/cloudera-scm-agent/process" ]
  then
    if [[ -z ${HUE_CONF_DIR} ]]
    then
      HUE_CONF_DIR="/var/run/cloudera-scm-agent/process/`ls -1 /var/run/cloudera-scm-agent/process | grep HUE_SERVER | sort -n | tail -1 `"
    fi
  else
    HUE_CONF_DIR="/etc/hue/conf"
  fi
  HUE_SUPERVISOR_CONF=$(echo ${HUE_CONF_DIR} | sed "s/process/supervisor\/include/g").conf
  export HUE_CONF_DIR HUE_SUPERVISOR_CONF

  if [[ ! ${USER} =~ .*root* ]]
  then
    if [[ -z ${OVERRIDE} ]]
    then
      echo "Script must be run as root: exiting"
      exit 1
    fi
  else
    if [[ $(ps -ef | grep "[h]ue runc" | awk '{print }') ]]
    then
      DESKTOP_LOG_DIR=$(strings /proc/$(ps -ef | grep "[h]ue\ runc" | awk '{print $2}')/environ | grep DESKTOP_LOG_DIR | awk -F\= '{print $2}')
    fi
  fi

  if [[ -z ${DESKTOP_LOG_DIR} ]]
  then
    DESKTOP_LOG_DIR=${HUE_CONF_DIR}/logs
  fi
  if [[ ! -f ${DESKTOP_LOG_DIR} ]]
  then
    mkdir -p ${DESKTOP_LOG_DIR}
  fi
  LOG_FILE=${DESKTOP_LOG_DIR}/`basename "$0" | awk -F\. '{print $1}'`.log
  LOG_ROTATE_SIZE=10 #MB before rotating, size in MB before rotating log to .1
  LOG_ROTATE_COUNT=5 #number of log files, so 20MB max
 
  if [ ! -d "/usr/lib/hadoop" ]
  then
    export $(sed "s/,/\\n/g" ${HUE_SUPERVISOR_CONF} | grep PARCELS_ROOT | sed "s/'//g")
    PARCEL_DIR=${PARCELS_ROOT}/CDH
    CDH_HOME=$PARCEL_DIR
  else
    CDH_HOME=/usr
  fi

  if [ -d "${CDH_HOME}/lib/hue/build/env/bin" ]
  then
    COMMAND="${CDH_HOME}/lib/hue/build/env/bin/hue shell"
    TEST_COMMAND="${CDH_HOME}/lib/hue/build/env/bin/hue dbshell"
  else
    COMMAND="${CDH_HOME}/share/hue/build/env/bin/hue shell"
    TEST_COMMAND="${CDH_HOME}/share/hue/build/env/bin/hue dbshell"
  fi

  ORACLE_ENGINE_CHECK=$(grep engine ${HUE_CONF_DIR}/hue* | grep -i oracle)
  if [[ ! -z ${ORACLE_ENGINE_CHECK} ]]
  then
    if [[ -z ${ORACLE_HOME} ]]
    then
      ORACLE_PARCEL=/opt/cloudera/parcels/ORACLE_INSTANT_CLIENT/instantclient_11_2
      if [[ -d ${ORACLE_PARCEL} ]]
      then
        ORACLE_HOME=${ORACLE_PARCEL}
        LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${ORACLE_HOME}
        export LD_LIBRARY_PATH ORACLE_HOME
      fi
    fi
    if [[ -z ${ORACLE_HOME} ]]
    then
      echo "It looks like you are using Oracle as your backend"
      echo "ORACLE_HOME must be set to the correct Oracle client"
      echo "before running this script"
      exit 1
    fi
  fi

  HUE_IGNORE_PASSWORD_SCRIPT_ERRORS=1
  if [[ -z ${HUE_DATABASE_PASSWORD} ]]
  then
    echo "CDH 5.5 and above requires that you set the environment variable:"
    echo "HUE_DATABASE_PASSWORD=<dbpassword>"
    exit 1
  fi
  PGPASSWORD=${HUE_DATABASE_PASSWORD}
  export CDH_HOME COMMAND HUE_IGNORE_PASSWORD_SCRIPT_ERRORS PGPASSWORD

  QUIT_COMMAND="quit"
  PG_ENGINE_CHECK=$(grep engine ${HUE_CONF_DIR}/hue* | grep -i postgres)
  if [[ ! -z ${PG_ENGINE_CHECK} ]]
  then
    QUIT_COMMAND='\q'
  fi

  if [[ $? -ne 0 ]]
  then
    echo "HUE_DATABASE_PASSWORD is incorrect.  Please check CM: http://${HOSTNAME}:7180/api/v5/cm/deployment and search for HUE_SERVER and database to find correct password"
    exit 1
  fi

  ${COMMAND} >> /dev/null 2>&1 <<EOF
LOGFILE = "${LOG_FILE}"
logrotatesize=${LOG_ROTATE_SIZE}
backupcount=${LOG_ROTATE_COUNT}
maxsize=${SIZE}

import gc
import inspect
import sys
import logging
import logging.handlers
import json
import time
import desktop.conf

LOG = logging.getLogger()
format = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
fh = logging.handlers.RotatingFileHandler(LOGFILE, maxBytes = (1048576*logrotatesize), backupCount = backupcount)
fh.setFormatter(format)
LOG.addHandler(fh)
LOG.setLevel(logging.INFO)
LOG.info('HUE_CONF_DIR: ${HUE_CONF_DIR}')
LOG.info("DB Engine: %s" % desktop.conf.DATABASE.ENGINE.get())
LOG.info("DB Name: %s" % desktop.conf.DATABASE.NAME.get())
LOG.info("DB User: %s" % desktop.conf.DATABASE.USER.get())
LOG.info("DB Host: %s" % desktop.conf.DATABASE.HOST.get())
LOG.info("DB Port: %s" % str(desktop.conf.DATABASE.PORT.get()))

def log_large_objects(maxsize = (10 * 1024 * 1024)):
  for obj in gc.get_objects():
    size = sys.getsizeof(obj, 0)
    if hasattr(obj, '__class__'):
      name = str(obj.__class__.__name__)
      if size > maxsize: 
        try:
          filename = inspect.getabsfile(obj.__class__)
          logging.info("Size %.2f KB -- Object of class: %s -- in file: %s " % (size / 1024, name, filename))
        except:
          pass


logging.info("Looking for objects in memory greater than %s KB" % maxsize)
log_large_objects(maxsize = maxsize) 


EOF

echo ""
echo "Logs can be found in ${SCRIPT_DIR}/logs"

unset PGPASSWORD

}

main "$@"

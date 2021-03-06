#!/bin/bash

#parse command line arguments
parse_arguments()
{
  # Test that we're using compatible getopt version.
  getopt -T > /dev/null
  if [[ $? -ne 4 ]]; then
    echo "Incompatible getopt version."
    exit 1
  fi

  HUE_AUTH_SERVER="LDAP"
  GETOPT=`getopt -n $0 -o u:,w:,s:,p:,i:,e,v,h \
      -l user:,password:,server:,workflowid:,port:,enablessl,verbose,help \
      -- "$@"`
  eval set -- "$GETOPT"
  while true;
  do
    case "$1" in
    -u|--user)
      HUE_USER=$2
      shift 2
      ;;
    -w|--password)
      HUE_PASSWORD=$2
      shift 2
      ;;
    -s|--server)
      HUE_SERVER=$2
      shift 2
      ;;
    -p|--port)
      HUE_PORT=$2
      shift 2
      ;;
    -i|--workflowid)
      WORKFLOW_ID=$2
      shift 2
      ;;
    -e|--enablessl)
      ENABLESSL=1
      shift
      ;;
    -v|--verbose)
      VERBOSE=1
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
  if [[ -z ${HUE_USER} ]]
  then
    HUE_USER="admin"
  fi
  if [[ -z ${HUE_PASSWORD} ]]
  then
    HUE_PASSWORD="admin"
  fi
  if [[ -z ${HUE_SERVER} ]]
  then
    HUE_SERVER="localhost"
  fi
  if [[ -z ${HUE_PORT} ]]
  then
    HUE_PORT="8888"
  fi
  if [[ -z ${WORKFLOW_ID} ]]
  then
    WORKFLOW_ID="0000005-170608063715515-oozie-oozi-W"
  fi

}

usage()
{
cat << EOF
usage: $0 [options]

Tests Hue Oozie:

OPTIONS
   -u|--user		   Hue username - default admin.
   -w|--password	   Hue password - default admin.
   -s|--server	           Hue server host - localhost.
   -p|--port               Hue server port - 8888.
   -i|--workflowid	   ID of a workflow that can be checked. Format: 0000005-170608063715515-oozie-oozi-W
   -h|--help               Show this message.
EOF
}

main()
{

   parse_arguments "$@"
   
   if [[ -z ${ENABLESSL} ]]
   then
      HUE_HTTP="http"
   else
      HUE_HTTP="https"
   fi
   URLENCODEPOUND='\%23'
   HUE_PASS_URL="${HUE_HTTP}://${HUE_SERVER}:${HUE_PORT}/accounts/login/"
   HUE_OOZIE_URL="${HUE_HTTP}://${HUE_SERVER}:${HUE_PORT}/oozie/?format=json&offset=1&status=SUCCEEDED&status=KILLED&status=FAILED"
#   HUE_OOZIE_URL="${HUE_HTTP}://${HUE_SERVER}:${HUE_PORT}/oozie/list_oozie_workflow/${WORKFLOW_ID}/"

   hue_login
   echo "Testing oozie"
   echo "$HUE_OOZIE_URL"
   do_curl \
        GET \
        "${HUE_OOZIE_URL}" 

}

function do_curl() {

   METHOD=$1
   shift
   URL=$1
   shift
   ARGS=$@

   CURL=$(which curl)
   if [ -z ${COOKIE_JAR} ]
   then
      COOKIE_JAR=/tmp/cookie.jar
   fi
   if [ -f ${COOKIE_JAR} ]
   then
      CSRF_TOKEN=`grep ${HUE_SERVER} ${COOKIE_JAR} | grep csrftoken | cut -f 7`
   fi
   if [ ! -f ${CURL} ]
   then
      echo "curl not found, unable to run any curl commands"
   else
      debug "Connecting to ${URL}"
      debug "${CURL} \
         ${CURL_OPTS} \
         -k \
         -e \"${HUE_HTTP}://${HUE_SERVER}:${HUE_PORT}/\" \
         -b @${COOKIE_JAR} \
         -c ${COOKIE_JAR} \
         -H \"X-CSRFToken: ${CSRF_TOKEN}\" \
         -X ${METHOD} \
         -f \
         ${URL} \
         ${ARGS}"

      ${CURL} \
         ${CURL_OPTS} \
         -k \
         -e "${HUE_HTTP}://${HUE_SERVER}:${HUE_PORT}/" \
         -b @${COOKIE_JAR} \
         -c ${COOKIE_JAR} \
         -H "X-CSRFToken: ${CSRF_TOKEN}" \
         -X ${METHOD} \
         -f \
         ${URL} \
         ${ARGS}
   fi

}

function hue_login() {
   echo "Login to Hue to get Cookie:"
   do_curl \
	GET \
	"${HUE_PASS_URL}" \
	-L 2>&1 > /dev/null

   do_curl \
        POST \
        "${HUE_PASS_URL}" \
        -F username=${HUE_USER} -F password="${HUE_PASSWORD}" -F server="${HUE_AUTH_SERVER}" 2>&1 > /dev/null
}

debug()
{
   if [[ ! -z $VERBOSE ]]
   then
      echo "$1"
   fi
}

main "$@"

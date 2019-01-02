#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

ZIGLEDGER_CA="$GOPATH/src/github.com/zhigui/zigledger-ca"
SCRIPTDIR="$ZIGLEDGER_CA/scripts/fvt"
. $SCRIPTDIR/zigledger-ca_utils
GO_VER="1.7.1"
ARCH="amd64"
RC=0

function usage() {
   echo "ARGS:"
   echo "  -d)   <DRIVER> - [sqlite3|mysql|postgres]"
   echo "  -n)   <ZIGLEDGER_CA_INSTANCES> - number of servers to start"
   echo "  -t)   <KEYTYPE> - rsa|ecdsa"
   echo "  -l)   <KEYLEN> - ecdsa: 256|384|521; rsa 2048|3072|4096"
   echo "  -c)   <SRC_CERT> - pre-existing server cert"
   echo "  -k)   <SRC_KEY> - pre-existing server key"
   echo "  -x)   <DATADIR> - local storage for client auth_info"
   echo "FLAGS:"
   echo "  -D)   set ZIGLEDGER_CA_DEBUG='true'"
   echo "  -R)   set RESET='true' - delete DB, server certs, client certs"
   echo "  -I)   set INIT='true'  - run zigledger-ca server init"
   echo "  -S)   set START='true' - start \$ZIGLEDGER_CA_INSTANCES number of servers"
   echo "  -X)   set PROXY='true' - start haproxy for \$ZIGLEDGER_CA_INSTANCES of zigledger-ca servers"
   echo "  -K)   set KILL='true'  - kill all running zigledger-ca instances and haproxy"
   echo "  -L)   list all running zigledger-ca instances"
   echo "  -P)   Enable profiling port on the server"
   echo " ?|h)  this help text"
   echo ""
   echo "Defaults: -d sqlite3 -n 1 -k ecdsa -l 256"
}

runPSQL() {
   local cmd="$1"
   local opts="$2"
   local wrk_dir="$(pwd)"
   cd /tmp
   /usr/bin/psql "$opts" -U postgres -h localhost -c "$cmd"
   local rc=$?
   cd $wrk_dir
   return $rc
}

resetZigledgerCa(){
   killAllZigledgerCas
   rm -rf $DATADIR >/dev/null
   test -f $(pwd)/${DBNAME}* && rm $(pwd)/${DBNAME}*
   cd /tmp

   # Base server and cluster servers
   for i in "" $(seq ${CACOUNT:-0}); do
      test -z $i && dbSuffix="" || dbSuffix="_ca$i"
      mysql --host=localhost --user=root --password=mysql -e 'show tables' ${DBNAME}${dbSuffix} >/dev/null 2>&1
         mysql --host=localhost --user=root --password=mysql -e "DROP DATABASE IF EXISTS ${DBNAME}${dbSuffix}" >/dev/null 2>&1
      /usr/bin/dropdb "${DBNAME}${dbSuffix}" -U postgres -h localhost -w --if-exists 2>/dev/null
   done
}

listZigledgerCa(){
   echo "Listening servers;"
   local port=${USER_CA_PORT-$CA_DEFAULT_PORT}
   local inst=0
   while test $((inst)) -lt $ZIGLEDGER_CA_INSTANCES; do
     lsof -n -i tcp:$((port+$inst))
     inst=$((inst+1))
   done

   # Base server and cluster servers
   for i in "" $(seq ${CACOUNT:-0}); do
      test -z $i && dbSuffix="" || dbSuffix="_ca$i"
      echo ""
      echo " ======================================"
      echo " ========> Dumping ${DBNAME}${dbSuffix} Database"
      echo " ======================================"
      case $DRIVER in
         mysql)
            echo ""
            echo "Users:"
            mysql --host=localhost --user=root --password=mysql -e 'SELECT * FROM users;' ${DBNAME}${dbSuffix}
            if $($ZIGLEDGER_CA_DEBUG); then
               echo "Certificates:"
               mysql --host=localhost --user=root --password=mysql -e 'SELECT * FROM certificates;' ${DBNAME}${dbSuffix}
               echo "Affiliations:"
               mysql --host=localhost --user=root --password=mysql -e 'SELECT * FROM affiliations;' ${DBNAME}${dbSuffix}
            fi
         ;;
         postgres)
            echo ""
            runPSQL "\l ${DBNAME}${dbSuffix}" | sed 's/^/   /;1s/^ *//;1s/$/:/'

            echo "Users:"
            runPSQL "SELECT * FROM USERS;" "--dbname=${DBNAME}${dbSuffix}" | sed 's/^/   /'
            if $($ZIGLEDGER_CA_DEBUG); then
               echo "Certificates::"
               runPSQL "SELECT * FROM CERTIFICATES;" "--dbname=${DBNAME}${dbSuffix}" | sed 's/^/   /'
               echo "Affiliations:"
               runPSQL "SELECT * FROM AFFILIATIONS;" "--dbname=${DBNAME}${dbSuffix}" | sed 's/^/   /'
            fi
         ;;
         sqlite3) test -z $i && DBDIR=$DATADIR || DBDIR="$DATADIR/ca/ca$i"
                  sqlite3 "$DBDIR/$DBNAME" 'SELECT * FROM USERS ;;' | sed 's/^/   /'
                  if $($ZIGLEDGER_CA_DEBUG); then
                     sqlite3 "$DATASRC" 'SELECT * FROM CERTIFICATES;' | sed 's/^/   /'
                     sqlite3 "$DATASRC" 'SELECT * FROM AFFILIATIONS;' | sed 's/^/   /'
                  fi
      esac
   done
}

function initZigledgerCa() {
   test -f $ZIGLEDGER_CA_SERVEREXEC || ErrorExit "zigledger-ca executable not found in src tree"

   $ZIGLEDGER_CA_SERVEREXEC init -c $RUNCONFIG $PARENTURL $args || return 1

   echo "ZIGLEDGER_CA server initialized"
   if $($ZIGLEDGER_CA_DEBUG); then
      openssl x509 -in $DATADIR/$DST_CERT -noout -issuer -subject -serial \
                   -dates -nameopt RFC2253| sed 's/^/   /'
      openssl x509 -in $DATADIR/$DST_CERT -noout -text |
         awk '
            /Subject Alternative Name:/ {
               gsub(/^ */,"")
               printf $0"= "
               getline; gsub(/^ */,"")
               print
            }'| sed 's/^/   /'
      openssl x509 -in $DATADIR/$DST_CERT -noout -pubkey |
         openssl $KEYTYPE -pubin -noout -text 2>/dev/null| sed 's/Private/Public/'
      openssl $KEYTYPE -in $DATADIR/$DST_KEY -text 2>/dev/null
   fi
}


function startHaproxy() {
   local inst=$1
   local i=0
   local proxypids=$(lsof -n -i tcp | awk '$1=="haproxy" && !($2 in a) {a[$2]=$2;print a[$2]}')
   test -n "$proxypids" && kill $proxypids
   local server_port=${USER_CA_PORT-$CA_DEFAULT_PORT}
   case $TLS_ON in
     "true")
   haproxy -f  <(echo "global
      log 127.0.0.1 local2
      daemon
defaults
      log     global
      option  dontlognull
      maxconn 4096
      timeout connect 30000
      timeout client 300000
      timeout server 300000

frontend haproxy
      bind *:$PROXY_PORT
      mode tcp
      option tcplog
      default_backend zigledger-cas

backend zigledger-cas
   mode tcp
   balance roundrobin";

   # For each requested instance passed to startHaproxy
   # (which is determined by the -n option passed to the
   # main script) create a backend server in haproxy config
   # Each server binds to a unique port on INADDR_ANY
   while test $((i)) -lt $inst; do
      echo "      server server$i  localhost:$((server_port+$i))"
      i=$((i+1))
   done
   i=0

if test -n "$ZIGLEDGER_CA_SERVER_PROFILE_PORT" ; then
echo "
frontend haproxy-profile
      bind *:8889
      mode http
      option tcplog
      default_backend zigledger-ca-profile

backend zigledger-ca-profile
      mode http
      http-request set-header X-Forwarded-Port %[dst_port]
      balance roundrobin";
   while test $((i)) -lt $inst; do
      echo "      server server$i  localhost:$((ZIGLEDGER_CA_SERVER_PROFILE_PORT+$i))"
      i=$((i+1))
   done
   i=0
fi

if test -n "$ZIGLEDGER_CA_INTERMEDIATE_SERVER_PORT" ; then
echo "
frontend haproxy-intcas
      bind *:$INTERMEDIATE_PROXY_PORT
      mode tcp
      option tcplog
      default_backend zigledger-intcas

backend zigledger-intcas
   mode tcp
   balance roundrobin";

   while test $((i)) -lt $inst; do
      echo "      server intserver$i  localhost:$((INTERMEDIATE_CA_DEFAULT_PORT+$i))"
      i=$((i+1))
   done
   i=0
fi
)
   ;;
   *)
   haproxy -f  <(echo "global
      log 127.0.0.1 local2
      daemon
defaults
      log     global
      mode http
      option  httplog
      option  dontlognull
      maxconn 4096
      timeout connect 30000
      timeout client 300000
      timeout server 300000
      option forwardfor

listen stats
      bind *:10888
      stats enable
      stats uri /
      stats enable

frontend haproxy
      bind *:$PROXY_PORT
      mode http
      option tcplog
      default_backend zigledger-cas

backend zigledger-cas
      mode http
      http-request set-header X-Forwarded-Port %[dst_port]
      balance roundrobin";
   while test $((i)) -lt $inst; do
      echo "      server server$i  localhost:$((server_port+$i))"
      i=$((i+1))
   done
   i=0

if test -n "$ZIGLEDGER_CA_SERVER_PROFILE_PORT" ; then
echo "
frontend haproxy-profile
      bind *:8889
      mode http
      option tcplog
      default_backend zigledger-ca-profile

backend zigledger-ca-profile
      mode http
      http-request set-header X-Forwarded-Port %[dst_port]
      balance roundrobin";
   while test $((i)) -lt $inst; do
      echo "      server server$i  localhost:$((ZIGLEDGER_CA_SERVER_PROFILE_PORT+$i))"
      i=$((i+1))
   done
   i=0
fi

if test -n "$ZIGLEDGER_CA_INTERMEDIATE_SERVER_PORT" ; then
echo "
frontend haproxy-intcas
      bind *:$INTERMEDIATE_PROXY_PORT
      mode http
      option tcplog
      default_backend zigledger-intcas

backend zigledger-intcas
      mode http
      http-request set-header X-Forwarded-Port %[dst_port]
      balance roundrobin";

   while test $((i)) -lt $inst; do
      echo "      server intserver$i  localhost:$((INTERMEDIATE_CA_DEFAULT_PORT+$i))"
      i=$((i+1))
   done
   i=0
fi
)
   ;;
   esac
}

function startZigledgerCa() {
   local inst=$1
   local start=$SECONDS
   local timeout="$TIMEOUT"
   local now=0
   local server_addr=0.0.0.0
   local polladdr=$server_addr
   local port=${USER_CA_PORT-$CA_DEFAULT_PORT}
   port=$((port+$inst))
   # if not explcitly set, use default
   test -n "${port}" && local server_port="--port $port" || local server_port=""
   test -n "${CACOUNT}" && local cacount="--cacount ${CACOUNT}"

   if test -n "$ZIGLEDGER_CA_SERVER_PROFILE_PORT" ; then
      local profile_port=$((ZIGLEDGER_CA_SERVER_PROFILE_PORT+$inst))
      ZIGLEDGER_CA_SERVER_PROFILE_PORT=$profile_port $ZIGLEDGER_CA_SERVEREXEC start --address $server_addr $server_port --ca.certfile $DST_CERT \
                     --ca.keyfile $DST_KEY --config $RUNCONFIG $PARENTURL 2>&1 &
   else
#      $ZIGLEDGER_CA_SERVEREXEC start --address $server_addr $server_port --ca.certfile $DST_CERT \
#                     --ca.keyfile $DST_KEY $cacount --config $RUNCONFIG $args > $DATADIR/server${port}.log 2>&1 &
      $ZIGLEDGER_CA_SERVEREXEC start --address $server_addr $server_port --ca.certfile $DST_CERT \
                     --ca.keyfile $DST_KEY $cacount --config $RUNCONFIG $args 2>&1 &
   fi

   printf "ZIGLEDGER_CA server on $server_addr:$port "
   test "$server_addr" = "0.0.0.0" && polladdr="127.0.0.1"
   pollZigledgerCa "" "$server_addr" "$port" "" "$TIMEOUT"
   if test "$?" -eq 0; then
      echo " STARTED"
   else
      RC=$((RC+1))
      echo " FAILED"
   fi
}

function killAllZigledgerCas() {
   local zigledger_capids=$(ps ax | awk '$5~/zigledger-ca/ {print $1}')
   local proxypids=$(lsof -n -i tcp | awk '$1=="haproxy" && !($2 in a) {a[$2]=$2;print a[$2]}')
   test -n "$zigledger_capids" && kill $zigledger_capids
   test -n "$proxypids" && kill $proxypids
}

while getopts "\?hRCISKXLDTAPNad:t:l:n:c:k:x:g:m:p:r:o:u:U:" option; do
  case "$option" in
     a)   LDAP_ENABLE="true" ;;
     o)   TIMEOUT="$OPTARG" ;;
     u)   CACOUNT="$OPTARG" ;;
     d)   DRIVER="$OPTARG" ;;
     r)   USER_CA_PORT="$OPTARG" ;;
     p)   HTTP_PORT="$OPTARG" ;;
     n)   ZIGLEDGER_CA_INSTANCES="$OPTARG" ;;
     t)   KEYTYPE=$(tolower $OPTARG);;
     l)   KEYLEN="$OPTARG" ;;
     c)   SRC_CERT="$OPTARG";;
     k)   SRC_KEY="$OPTARG" ;;
     x)   CA_CFG_PATH="$OPTARG" ;;
     m)   MAXENROLL="$OPTARG" ;;
     g)   SERVERCONFIG="$OPTARG" ;;
     U)   PARENTURL="$OPTARG" ;;
     D)   export ZIGLEDGER_CA_DEBUG='true' ;;
     A)   AUTH="false" ;;
     R)   RESET="true"  ;;
     I)   INIT="true" ;;
     S)   START="true" ;;
     X)   PROXY="true" ;;
     K)   KILL="true" ;;
     L)   LIST="true" ;;
     T)   TLS_ON="true" ;;
     P)   export ZIGLEDGER_CA_SERVER_PROFILE_PORT=$PROFILING_PORT ;;
     N)   export ZIGLEDGER_CA_INTERMEDIATE_SERVER_PORT=$INTERMEDIATE_CA_DEFAULT_PORT;;
   \?|h)  usage
          exit 1
          ;;
  esac
done

shift $((OPTIND-1))
args=$@
: ${LDAP_ENABLE:="false"}
: ${TIMEOUT:=$DEFAULT_TIMEOUT}
: ${HTTP_PORT:="3755"}
: ${DBNAME:="zigledger_ca"}
: ${MAXENROLL:="-1"}
: ${AUTH:="true"}
: ${DRIVER:="sqlite3"}
: ${ZIGLEDGER_CA_INSTANCES:=1}
: ${ZIGLEDGER_CA_DEBUG:="false"}
: ${LIST:="false"}
: ${RESET:="false"}
: ${INIT:="false"}
: ${START:="false"}
: ${PROXY:="false"}
: ${HTTP:="true"}
: ${KILL:="false"}
: ${KEYTYPE:="ecdsa"}
: ${KEYLEN:="256"}
: ${CACOUNT=""}
test $KEYTYPE = "rsa" && SSLKEYCMD=$KEYTYPE || SSLKEYCMD="ec"
test -n "$PARENTURL" && PARENTURL="-u $PARENTURL"

: ${CA_CFG_PATH:="/tmp/zigledger-ca"}
: ${DATADIR:="$CA_CFG_PATH"}
export CA_CFG_PATH

# regarding tls:
#    honor the command-line setting to turn on TLS
#      else honor the envvar
#        else (default) turn off tls
sslmode=disable
if test -n "$TLS_ON"; then
   TLS_DISABLE='false'; LDAP_PORT=636; LDAP_PROTO="ldaps://";sslmode="require";mysqlTls='&tls=custom'
else
   case "$ZIGLEDGER_TLS" in
      true) TLS_DISABLE='false';TLS_ON='true'; LDAP_PORT=636; LDAP_PROTO="ldaps://";sslmode="require";mysqlTls='&tls=custom' ;;
     false) TLS_DISABLE='true' ;TLS_ON='false' ;;
         *) TLS_DISABLE='true' ;TLS_ON='false' ;;
   esac
fi

test -d $DATADIR || mkdir -p $DATADIR
DST_KEY="zigledger-ca-key.pem"
DST_CERT="zigledger-ca-cert.pem"
test -n "$SRC_CERT" && cp "$SRC_CERT" $DATADIR/$DST_CERT
test -n "$SRC_KEY" && cp "$SRC_KEY" $DATADIR/$DST_KEY
RUNCONFIG="$DATADIR/runZigledgerCaFvt.yaml"

case $DRIVER in
   postgres) DATASRC="dbname=$DBNAME host=127.0.0.1 port=$POSTGRES_PORT user=postgres password=postgres sslmode=$sslmode" ;;
   sqlite3)  DATASRC="$DBNAME" ;;
   mysql)    DATASRC="root:mysql@tcp(localhost:$MYSQL_PORT)/$DBNAME?parseTime=true$mysqlTls" ;;
esac

$($LIST)  && listZigledgerCa
$($RESET) && resetZigledgerCa
$($KILL)  && killAllZigledgerCas
$($PROXY) && startHaproxy $ZIGLEDGER_CA_INSTANCES

$( $INIT -o $START ) && genRunconfig "$RUNCONFIG" "$DRIVER" "$DATASRC" "$DST_CERT" "$DST_KEY" "$MAXENROLL"
test -n "$SERVERCONFIG" && cp "$SERVERCONFIG" "$RUNCONFIG"

$($INIT) && initZigledgerCa
if $($START); then
   inst=0
   while test $((inst)) -lt $ZIGLEDGER_CA_INSTANCES; do
      startZigledgerCa $inst
      inst=$((inst+1))
   done
fi
exit $RC
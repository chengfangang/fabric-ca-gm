#!/bin/bash
: ${TESTCASE="version"}
ZIGLEDGER_CA="$GOPATH/src/github.com/zhigui/zigledger-ca"
SCRIPTDIR="$ZIGLEDGER_CA/scripts/fvt"
. $SCRIPTDIR/zigledger-ca_utils
RC=0
DRIVER=sqlite3
CA_CFG_PATH="/tmp/$TESTCASE"

capath="$1"
test -z "$capath" && capath=$ZIGLEDGER_CA/bin

ZIGLEDGER_CA_CLIENTEXEC="$capath/zigledger-ca-client"
ZIGLEDGER_CA_SERVEREXEC="$capath/zigledger-ca-server"
test -x $ZIGLEDGER_CA_CLIENTEXEC || ZIGLEDGER_CA_CLIENTEXEC="$(which zigledger-ca-client)"
test -x $ZIGLEDGER_CA_SERVEREXEC || ZIGLEDGER_CA_SERVEREXEC="$(which zigledger-ca-server)"
test -x $ZIGLEDGER_CA_CLIENTEXEC || ZIGLEDGER_CA_CLIENTEXEC="/usr/local/bin/zigledger-ca-client"
test -x $ZIGLEDGER_CA_SERVEREXEC || ZIGLEDGER_CA_SERVEREXEC="/usr/local/bin zigledger-ca-server"
test -z "$ZIGLEDGER_CA_CLIENTEXEC" -o -z "$ZIGLEDGER_CA_SERVEREXEC" && ErrorExit "Cannot find executables"

function checkVersion() {
   awk -v ver=$1 \
       -v rc=1 \
         '$1=="Version:" && $NF==ver {rc=0}
          END {exit rc}'
}

base_version=$(awk '/^[:blank:]*BASE_VERSION/ {print $NF}' Makefile)
extra_version="snapshot-$(git rev-parse --short HEAD)"
if [ "$IS_RELEASE" = "true" ]; then
   project_version=${base_version}
else
   project_version=${base_version}-${extra_version}
fi
echo "Project version is: $project_version"

trap "CleanUp 1; exit 1" INT
$ZIGLEDGER_CA_SERVEREXEC version | checkVersion "$project_version" || let RC+=1
$ZIGLEDGER_CA_CLIENTEXEC version | checkVersion "$project_version" || let RC+=1

CleanUp $RC
exit $RC

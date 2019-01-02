#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

ZIGLEDGER_CA="$GOPATH/src/github.com/zhigui/zigledger-ca"
ZIGLEDGER_CAEXEC="$ZIGLEDGER_CA/bin/zigledger-ca"
TESTDATA="$ZIGLEDGER_CA/testdata"
SCRIPTDIR="$ZIGLEDGER_CA/scripts/fvt"
HOST="http://localhost:$PROXY_PORT"
RC=0
$($ZIGLEDGER_TLS) && HOST="https://localhost:$PROXY_PORT"
. $SCRIPTDIR/zigledger-ca_utils

while getopts "u:t:g:a:x:" option; do
  case "$option" in
     x)   ZIGLEDGER_HOME="$OPTARG" ;;
     u)   USERNAME="$OPTARG" ;;
     t)   USERTYPE="$OPTARG" ;;
     g)   USERGRP="$OPTARG";
          test -z "$USERGRP" && NULLGRP='true' ;;
     a)   USERATTR="$OPTARG" ;;
  esac
done

test -z "$ZIGLEDGER_HOME" && ZIGLEDGER_HOME="$HOME/zigledger-ca"

: ${NULLGRP:="false"}
: ${USERNAME:="testuser"}
: ${USERTYPE:="client"}
: ${USERGRP:="bank_a"}
$($NULLGRP) && unset USERGRP
: ${USERATTR:='[{"name":"test","value":"testValue"}]'}
: ${ZIGLEDGER_CA_DEBUG="false"}

genClientConfig "$ZIGLEDGER_HOME/zigledger-ca_client.json"

$ZIGLEDGER_CAEXEC client register <(echo "{
  \"id\": \"$USERNAME\",
  \"type\": \"$USERTYPE\",
  \"group\": \"$USERGRP\",
  \"attrs\": $USERATTR }") $HOST
RC=$?
exit $RC

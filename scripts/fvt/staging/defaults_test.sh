#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

ZIGLEDGER_CA="$GOPATH/src/github.com/zhigui/zigledger-ca"
ZIGLEDGER_EXEC="$ZIGLEDGER_CA/bin/zigledger-ca"
SCRIPTDIR="$ZIGLEDGER_CA/scripts/fvt"
TESTDATA="$ZIGLEDGER_CA/testdata"
DST_KEY=$TESTDATA/ec-key.pem
DST_CERT=$TESTDATA/ec.pem
RUNCONFIG=$TESTDATA/testconfig.json
ZIGLEDGER_PID=""
. $SCRIPTDIR/zigledger-ca_utils
RC=0

function startZigledgerCa() {
   local start=$SECONDS
   local timeout=8
   local now=0
   # if not explcitly set, use default
   if test -n "$1"; then
      local server_addr="-address $1"
      local addr=$1
   fi
   if test -n "$2"; then
      local server_port="-port $2"
      local port="$2"
   fi

   $ZIGLEDGER_EXEC server start $server_addr $server_port -ca $DST_CERT -ca-key $DST_KEY -config $RUNCONFIG &
   ZIGLEDGER_PID=$!
   until test "$started" = "${addr-127.0.0.1}:${port-$CA_DEFAULT_PORT}" -o "$now" -gt "$timeout"; do
      started="$(ss -ltnp src "${addr-127.0.0.1}:${port-$CA_DEFAULT_PORT}" | awk 'NR!=1 {print $4}')"
      sleep .5
      let now+=1
   done
   test "$started" = "${addr-127.0.0.1}:${port-$CA_DEFAULT_PORT}" && return 0 || return 1
}

startZigledgerCa
test $? -ne 0 && ErrorMsg "Server start default addr/port failed"
kill $ZIGLEDGER_PID
wait $ZIGLEDGER_PID

startZigledgerCa 127.0.0.2 3755
test $? -ne 0 && ErrorMsg "Server start user-defined addr/port failed"
echo $?
kill $ZIGLEDGER_PID
wait $ZIGLEDGER_PID

CleanUp $RC
exit $RC

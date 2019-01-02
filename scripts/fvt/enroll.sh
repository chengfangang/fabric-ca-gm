#!/bin/bash

#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

ZIGLEDGER_CA="$GOPATH/src/github.com/zhigui/zigledger-ca"
SCRIPTDIR="$ZIGLEDGER_CA/scripts/fvt"
. $SCRIPTDIR/zigledger-ca_utils
RC=0

while getopts "du:p:t:l:x:" option; do
  case "$option" in
     d)   ZIGLEDGER_CA_DEBUG="true" ;;
     x)   CA_CFG_PATH="$OPTARG" ;;
     u)   USERNAME="$OPTARG" ;;
     p)   USERPSWD="$OPTARG" ;;
     t)   KEYTYPE="$OPTARG" ;;
     l)   KEYLEN="$OPTARG" ;;
  esac
done
test -z "$CA_CFG_PATH" && CA_CFG_PATH="$HOME/zigledger-ca"
test -f "$CA_CFG_PATH" || mkdir -p $CA_CFG_PATH

: ${ZIGLEDGER_CA_DEBUG="false"}
: ${USERNAME="admin"}
: ${USERPSWD="adminpw"}
: ${KEYTYPE="ecdsa"}
: ${KEYLEN="256"}

test "$KEYTYPE" = "ecdsa" && sslcmd="ec"

test -d "$CA_CFG_PATH/$USERNAME" || mkdir -p $CA_CFG_PATH/$USERNAME
cat > $CA_CFG_PATH/$USERNAME/zigledger-ca-client-config.yaml <<EOF
csr:
  cn: $USERNAME
  keyrequest:
    algo: $KEYTYPE
    size: $KEYLEN
EOF

$ZIGLEDGER_CA_CLIENTEXEC enroll -u "http://$USERNAME:$USERPSWD@$CA_HOST_ADDRESS:$PROXY_PORT" -H $CA_CFG_PATH/$USERNAME
RC=$?
CLIENTCERT="$CA_CFG_PATH/$USERNAME/msp/signcerts/cert.pem"
lastkey=$(ls -crtd $CA_CFG_PATH/$USERNAME/msp/keystore/* | tail -n1)
test -n "$lastkey" && CLIENTKEY="$lastkey" || CLIENTKEY="$CA_CFG_PATH/$USERNAME/msp/keystore/key.pem"
$($ZIGLEDGER_CA_DEBUG) && printAuth "$CLIENTCERT" "$CLIENTKEY"
exit $RC

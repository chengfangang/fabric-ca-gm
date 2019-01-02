# !/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

ZIGLEDGER_CA="$GOPATH/src/github.com/zhigui/zigledger-ca"
ZIGLEDGER_CAEXEC="$ZIGLEDGER_CA/bin/zigledger-ca"
TESTDATA="$ZIGLEDGER_CA/testdata"
SCRIPTDIR="$ZIGLEDGER_CA/scripts/fvt"
CSR="$TESTDATA/csr.json"
HOST="http://localhost:$PROXY_PORT"
RUNCONFIG="$TESTDATA/postgres.json"
INITCONFIG="$TESTDATA/csr_ecdsa256.json"
RC=0
$($ZIGLEDGER_TLS) && HOST="https://localhost:$PROXY_PORT"

. $SCRIPTDIR/zigledger-ca_utils

: ${ZIGLEDGER_CA_DEBUG="false"}

while getopts "k:l:x:" option; do
  case "$option" in
     x)   CA_CFG_PATH="$OPTARG" ;;
     k)   KEYTYPE="$OPTARG" ;;
     l)   KEYLEN="$OPTARG" ;;
  esac
done

: ${KEYTYPE="ecdsa"}
: ${KEYLEN="256"}
: ${ZIGLEDGER_CA_DEBUG="false"}
test -z "$CA_CFG_PATH" && CA_CFG_PATH=$HOME/zigledger-ca
CLIENTCERT="$CA_CFG_PATH/cert.pem"
CLIENTKEY="$CA_CFG_PATH/key.pem"
export CA_CFG_PATH

genClientConfig "$CA_CFG_PATH/client-config.json"
$ZIGLEDGER_CAEXEC client reenroll $HOST <(echo "{
    \"hosts\": [
        \"admin@fab-client.raleigh.ibm.com\",
        \"fab-client.raleigh.ibm.com\",
        \"127.0.0.2\"
    ],
    \"key\": {
        \"algo\": \"$KEYTYPE\",
        \"size\": $KEYLEN
    },
    \"names\": [
        {
            \"O\": \"Zhigui\",
            \"O\": \"Zigledger\",
            \"OU\": \"ZIGLEDGER_CA\",
            \"OU\": \"FVT\",
            \"STREET\": \"Miami Blvd.\",
            \"DC\": \"peer\",
            \"UID\": \"admin\",
            \"L\": \"Raleigh\",
            \"L\": \"RTP\",
            \"ST\": \"North Carolina\",
            \"C\": \"US\"
        }
    ]
}")
RC=$?
$($ZIGLEDGER_CA_DEBUG) && printAuth $CLIENTCERT $CLIENTKEY
exit $RC

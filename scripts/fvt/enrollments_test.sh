#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

ZIGLEDGER_CA="$GOPATH/src/github.com/zhigui/zigledger-ca"
SCRIPTDIR="$ZIGLEDGER_CA/scripts/fvt"
. $SCRIPTDIR/zigledger-ca_utils
CA_CFG_PATH="/tmp/zigledger-ca/enrollments"
SERVERCONFIG="$CA_CFG_PATH/serverConfig.json"
CLIENTCONFIG="$CA_CFG_PATH/zigledger-ca_client.json"
CLIENTCERT="$CA_CFG_PATH/admin/$MSP_CERT_DIR/cert.pem"
PKI="$SCRIPTDIR/utils/pki"
MAX_ENROLL="$1"
UNLIMITED=10
RC=0
: ${MAX_ENROLL:="32"}
: ${DRIVER:="sqlite3"}
: ${DATASRC:="zigledger-ca-server.db"}
: ${ZIGLEDGER_CA_DEBUG:="false"}
export CA_CFG_PATH

function genServerConfig {
case "$1" in
   implicit) cat > $SERVERCONFIG <<EOF
debug: true
db:
  type: $DRIVER
  datasource: $DATASRC
  tls:
    certfiles:
      - $TLS_ROOTCERT
    client:
      certfile: $TLS_CLIENTCERT
      keyfile: $TLS_CLIENTKEY
tls:
  enabled: $ZIGLEDGER_TLS
  certfile: $TLS_SERVERCERT
  keyfile: $TLS_SERVERKEY
ca:
  certfile: $CA_CFG_PATH/zigledger-ca-key.pem
  keyfile: $CA_CFG_PATH/zigledger-ca-cert.pem
registry:
  identities:
     - name: admin
       pass: adminpw
       type: client
       affiliation: bank_a
       attributes:
        - hf.Registrar.Roles: "client,user,peer,validator,auditor,ca"
          hf.Registrar.DelegateRoles: "client,user,validator,auditor"
          hf.Revoker: true
ldap:
  enabled: false
  url: ${LDAP_PROTO}CN=admin,dc=example,dc=com:adminpw@localhost:$LDAP_PORT/dc=example,dc=com
  tls:
     certfiles:
       - $TLS_ROOTCERT
     client:
       certfile: $TLS_CLIENTCERT
       keyfile: $TLS_CLIENTKEY
affiliations:
   bank_a:
signing:
    profiles:
    default:
      usage:
        - cert sign
      expiry: 8000h
csr:
   cn: zigledger-ca-server
   names:
      - C: US
        ST: "North Carolina"
        L:
        O: Zhigui
        OU: Zigledger
   hosts:
     - amphion
   ca:
      pathlen:
      pathlenzero:
      expiry:
crypto:
  software:
     hash_family: SHA2
     security_level: 256
     ephemeral: false
     key_store_dir: keys
EOF
;;
   # Max enroll for identities cannot surpass global setting
   invalid) cat > $SERVERCONFIG <<EOF
debug: true
db:
  type: $DRIVER
  datasource: $DATASRC
  tls:
    certfiles:
      - $TLS_ROOTCERT
    client:
      certfile: $TLS_CLIENTCERT
      keyfile: $TLS_CLIENTKEY
tls:
  enabled: $ZIGLEDGER_TLS
  certfile: $TLS_SERVERCERT
  keyfile: $TLS_SERVERKEY
ca:
  certfile: $CA_CFG_PATH/zigledger-ca-key.pem
  keyfile: $CA_CFG_PATH/zigledger-ca-cert.pem
registry:
  maxEnrollments: 15
  identities:
     - name: admin
       maxEnrollments: 16
       pass: adminpw
       type: client
       affiliation: bank_a
       attributes:
        - hf.Registrar.Roles: "client,user,peer,validator,auditor,ca"
          hf.Registrar.DelegateRoles: "client,user,validator,auditor"
          hf.Revoker: true
ldap:
  enabled: false
  url: ${LDAP_PROTO}CN=admin,dc=example,dc=com:adminpw@localhost:$LDAP_PORT/dc=example,dc=com
  tls:
    certfiles:
      - $TLS_ROOTCERT
    client:
      certfile: $TLS_CLIENTCERT
      keyfile: $TLS_CLIENTKEY
affiliations:
   bank_a:
signing:
    profiles:
    default:
      usage:
        - cert sign
      expiry: 8000h
csr:
   cn: zigledger-ca-server
   names:
      - C: US
        ST: "North Carolina"
        L:
        O: Zhigui
        OU: Zigledger
   hosts:
     - amphion
   ca:
      pathlen:
      pathlenzero:
      expiry:
crypto:
  software:
     hash_family: SHA2
     security_level: 256
     ephemeral: false
     key_store_dir: keys
EOF
;;
esac
}

trap "CleanUp 1; exit 1" INT
# explicitly set value
   # user can only enroll MAX_ENROLL times
   $SCRIPTDIR/zigledger-ca_setup.sh -R -x $CA_CFG_PATH
   $SCRIPTDIR/zigledger-ca_setup.sh -D -I -S -X -m $MAX_ENROLL
   i=0
   while test $((i++)) -lt "$MAX_ENROLL"; do
      enroll
      test $? -eq 0 || ErrorMsg "Failed enrollment prematurely"
      currId=$($PKI -f display -c $CLIENTCERT | awk '/Subject Key Identifier:/ {getline;print $1}')
      test "$currId" == "$prevId" && ErrorMsg "Prior and current certificates do not differ"
      prevId="$currId"
   done
   # max reached -- should fail
   enroll
   test "$?" -eq 0 && ErrorMsg "Surpassed enrollment maximum"
   currId=$($PKI -f display -c $CLIENTCERT | awk '/Subject Key Identifier:/ {getline;print $1}')
   test "$currId" != "$prevId" && ErrorMsg "Prior and current certificates are different"
   prevId="$currId"


# explicitly set value to '1'
   # user can only enroll once
   MAX_ENROLL=1
   $SCRIPTDIR/zigledger-ca_setup.sh -R -x $CA_CFG_PATH
   $SCRIPTDIR/zigledger-ca_setup.sh -D -I -S -X -m $MAX_ENROLL
   i=0
   while test $((i++)) -lt "$MAX_ENROLL"; do
      enroll
      test $? -eq 0 || ErrorMsg "Failed enrollment prematurely"
      currId=$($PKI -f display -c $CLIENTCERT | awk '/Subject Key Identifier:/ {getline;print $1}')
      test "$currId" == "$prevId" && ErrorMsg "Prior and current certificates do not differ"
      prevId="$currId"
   done
   # max reached -- should fail
   enroll
   test "$?" -eq 0 && ErrorMsg "Surpassed enrollment maximum"
   currId=$($PKI -f display -c $CLIENTCERT | awk '/Subject Key Identifier:/ {getline;print $1}')
   test "$currId" != "$prevId" && ErrorMsg "Prior and current certificates are different"
   prevId="$currId"

# explicitly set value to '-1'
   # user enrollment unlimited
   MAX_ENROLL=-1
   $SCRIPTDIR/zigledger-ca_setup.sh -R -x $CA_CFG_PATH
   $SCRIPTDIR/zigledger-ca_setup.sh -D -I -S -X -m $MAX_ENROLL
   i=0
   while test $((i++)) -lt "$UNLIMITED"; do
      enroll
      test $? -eq 0 || ErrorMsg "Failed enrollment prematurely"
      currId=$($PKI -f display -c $CLIENTCERT | awk '/Subject Key Identifier:/ {getline;print $1}')
      test "$currId" == "$prevId" && ErrorMsg "Prior and current certificates do not differ"
      prevId="$currId"
   done

# implicitly set value to '-1' (default)
   # user enrollment unlimited
   $SCRIPTDIR/zigledger-ca_setup.sh -R -x $CA_CFG_PATH
   test -d $CA_CFG_PATH || mkdir $CA_CFG_PATH
   genServerConfig implicit
   $SCRIPTDIR/zigledger-ca_setup.sh -S -X -g $SERVERCONFIG
   i=0
   while test $((i++)) -lt "$UNLIMITED"; do
      enroll
      test $? -eq 0 || ErrorMsg "Failed enrollment prematurely"
      currId=$($PKI -f display -c $CLIENTCERT | awk '/Subject Key Identifier:/ {getline;print $1}')
      test "$currId" == "$prevId" && ErrorMsg "Prior and current certificates do not differ"
      prevId="$currId"
   done

   # user enrollment > global
   $SCRIPTDIR/zigledger-ca_setup.sh -R -x $CA_CFG_PATH
   test -d $CA_CFG_PATH || mkdir $CA_CFG_PATH
   genServerConfig invalid
   $SCRIPTDIR/zigledger-ca_setup.sh -o 0 -S -X -g $SERVERCONFIG | grep 'Configuration Error: Requested enrollments (16) exceeds maximum allowable enrollments (15)'
   test $? -ne 0 && ErrorMsg "user enrollment > global setting"

$SCRIPTDIR/zigledger-ca_setup.sh -L
$SCRIPTDIR/zigledger-ca_setup.sh -R -x $CA_CFG_PATH
CleanUp $RC
exit $RC

#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

num=$1
: ${num:=1}
ZIGLEDGER_CA="$GOPATH/src/github.com/zhigui/zigledger-ca"
SCRIPTDIR="$ZIGLEDGER_CA/scripts/fvt"
$SCRIPTDIR/zigledger-ca_setup.sh -R
$SCRIPTDIR/zigledger-ca_setup.sh -I -X -S -n $num

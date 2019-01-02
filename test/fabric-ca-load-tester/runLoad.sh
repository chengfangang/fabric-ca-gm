#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
# This script is used to run the load driver that drives load against a
# Zigledger CA server or cluster of servers. The Zigledger CA server URL and
# load characteristics can be defined in the testConfig.yml file, which
# must be located in the current working directory.
#
# When run with -B option, it will build the load driver and then runs it.

pushd $GOPATH/src/github.com/zhigui/zigledger-ca/test/zigledger-ca-load-tester
if [ "$1" == "-B" ]; then
  echo "Building zigledger-ca-load-tester..."
  if [ "$(uname)" == "Darwin" ]; then
    # On MacOS Sierra use -ldflags -s flags to work around "Killed: 9" error
    go build -o zigledger-ca-load-tester -ldflags -s main.go testClient.go
  else
    go build -o zigledger-ca-load-tester main.go testClient.go
  fi
fi
echo "Running load"
./zigledger-ca-load-tester -config testConfig.yml
rm -rf msp
rm -rf zigledger-ca-load-tester
popd

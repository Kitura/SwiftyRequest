#!/bin/bash
set -ex

cd TestServer
swift build
.build/debug/TestServer &
export TESTSERVER_PID=$!
sleep 1
cd ..

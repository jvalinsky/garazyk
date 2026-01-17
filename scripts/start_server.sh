#!/bin/bash
cd "$(dirname "$0")/.."
./build/bin/september > server.log 2>&1 &
echo $! > server.pid
echo "Server started with PID $(cat server.pid)"
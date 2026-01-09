#!/bin/bash
cd /Users/jack/Software/objpds
/Users/jack/Library/Developer/Xcode/DerivedData/ATProtoPDS-gxvfspcaobaihodzeszdnsruddhc/Build/Products/Debug/atprotopds serve --port 2583 --verbose > server.log 2>&1 &
echo $! > server.pid
echo "Server started with PID $(cat server.pid)"
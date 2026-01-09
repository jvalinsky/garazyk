#!/bin/bash
cd /Users/jack/Software/objpds
/Users/jack/Library/Developer/Xcode/DerivedData/ATProtoPDS-geyoohdrpdsipvgxpzswlfxtwriu/Build/Products/Debug/atprotopds > server.log 2>&1 &
echo $! > server.pid
echo "Server started with PID $(cat server.pid)"
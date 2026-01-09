#!/bin/bash
cd "$(dirname "$0")/../tool-plc"
npm install > /dev/null 2>&1
node server.js

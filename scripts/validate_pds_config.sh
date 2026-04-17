#!/bin/bash
# validate_pds_config.sh
# Validates PDS configuration for production security standards.

CONFIG_PATH=${1:-"docker/pds/config.json"}

if [ ! -f "$CONFIG_PATH" ]; then
    echo "Error: Config file not found at $CONFIG_PATH"
    exit 1
fi

echo "Validating PDS config: $CONFIG_PATH"

# Helper to check JSON values using python (more portable than jq for simple checks)
check_val() {
    local key=$1
    local expected=$2
    # Strip comments (C-style) before parsing
    local val=$(python3 -c "import json, re; c=open('$CONFIG_PATH').read(); c=re.sub(r'/\*.*?\*/', '', c, flags=re.DOTALL); d=json.loads(c, strict=False); print(d$key)" 2>/dev/null)
    
    if [ "$val" != "$expected" ]; then
        echo "FAIL: $key expected '$expected', got '$val'"
        return 1
    fi
    echo "PASS: $key is '$val'"
    return 0
}

RET=0

# Secure Defaults — MANDATORY
check_val "['session']['invite_code_required']" "True" || RET=1
check_val "['plc']['url']" "https://plc.directory" || RET=1
check_val "['rate_limit']['enabled']" "True" || RET=1

# Check for any debug flags enabled
DEBUG_FLAGS=$(python3 -c "import json, re; c=open('$CONFIG_PATH').read(); c=re.sub(r'/\*.*?\*/', '', c, flags=re.DOTALL); d=json.loads(c, strict=False); print(json.dumps(d.get('debug', {})))" 2>/dev/null)
if [[ "$DEBUG_FLAGS" == *"true"* ]]; then
    echo "FAIL: Debug flags enabled in $DEBUG_FLAGS"
    RET=1
fi

if [ $RET -eq 0 ]; then
    echo "Config validation SUCCESS"
else
    echo "Config validation FAILED"
fi

exit $RET

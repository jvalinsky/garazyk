#!/bin/bash
# validate_pds_config.sh
# Validates PDS configuration for production security standards.

CONFIG_PATH=${1:-"docker/pds/config.json"}

if [ ! -f "$CONFIG_PATH" ]; then
    echo "Error: Config file not found at $CONFIG_PATH"
    exit 1
fi

echo "Validating PDS config: $CONFIG_PATH"

# Helper to check JSON values without requiring jq.
check_val() {
    local key=$1
    local expected=$2
    # Strip comments (C-style) before parsing
    local val
    val=$(CONFIG_PATH="$CONFIG_PATH" KEY_EXPR="$key" deno eval 'const path = Deno.env.get("CONFIG_PATH"); const expr = Deno.env.get("KEY_EXPR") ?? ""; const text = await Deno.readTextFile(path); const data = JSON.parse(text.replace(/\/\*[\s\S]*?\*\//g, "")); const value = Function("d", `return d${expr}`)(data); console.log(String(value));' 2>/dev/null)
    
    if [ "$val" != "$expected" ]; then
        echo "FAIL: $key expected '$expected', got '$val'"
        return 1
    fi
    echo "PASS: $key is '$val'"
    return 0
}

RET=0

# Secure Defaults — MANDATORY
check_val "['session']['invite_code_required']" "true" || RET=1
check_val "['plc']['url']" "https://plc.directory" || RET=1
check_val "['rate_limit']['enabled']" "true" || RET=1

# Check for any debug flags enabled
DEBUG_FLAGS=$(CONFIG_PATH="$CONFIG_PATH" deno eval 'const text = await Deno.readTextFile(Deno.env.get("CONFIG_PATH")); const data = JSON.parse(text.replace(/\/\*[\s\S]*?\*\//g, "")); console.log(JSON.stringify(data.debug ?? {}));' 2>/dev/null)
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

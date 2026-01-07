#!/bin/bash

# PDS Documentation Build Script
# Generates HTML documentation using HeaderDoc

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/ATProtoPDS/ATProtoPDS"
OUTPUT_DIR="$SCRIPT_DIR/docs/html"

echo "Building PDS Documentation..."
echo "Source: $SRC_DIR"
echo "Output: $OUTPUT_DIR"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Files to document (output_name:source_path)
# Format: output_name source_file
DOCUMENTED_FILES="
PDSController PDSController.h
PDSDatabase Database/PDSDatabase.h
MST Repository/MST.h
CAR Repository/CAR.h
Session Auth/Session.h
OAuth2 Auth/OAuth2.h
JWT Auth/JWT.h
HttpServer Network/HttpServer.h
XrpcHandler Network/XrpcHandler.h
XrpcMethodRegistry Network/XrpcMethodRegistry.h
PDSMetrics Metrics/PDSMetrics.h
PDSAdminAuth Admin/PDSAdminAuth.h
PDSAdminHandler Admin/PDSAdminHandler.h
PDSLogger Debug/PDSLogger.h
PDSCLIDefinitions Tools/pds-cli/PDSCLIDefinitions.h
"

# Generate documentation for each file
echo "$DOCUMENTED_FILES" | while read output_name source_file; do
    if [ -n "$output_name" ]; then
        filepath="$SRC_DIR/$source_file"
        if [ -f "$filepath" ]; then
            echo "  Documenting: $source_file"
            # Create output directory for this file
            file_output_dir="$OUTPUT_DIR/${output_name}_h"
            mkdir -p "$file_output_dir"
            # Generate documentation with proper output path
            headerdoc2html -q -o "$file_output_dir" "$filepath" 2>&1 | grep -v "^$" || true
        else
            echo "  Warning: File not found: $filepath"
        fi
    fi
done

# Create a master table of contents
echo "Creating master documentation index..."

cat > "$OUTPUT_DIR/index.html" << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>ATProto PDS Documentation</title>
    <meta charset="UTF-8">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }
        h1 { color: #333; }
        h2 { color: #555; margin-top: 30px; }
        ul { line-height: 1.8; }
        a { color: #007AFF; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .category { background: white; padding: 20px; border-radius: 8px; margin: 10px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
    </style>
</head>
<body>
    <h1>ATProto PDS Documentation</h1>
    <p>Objective-C documentation for the ATProto Personal Data Server implementation.</p>
    
    <div class="category">
        <h2>Core Components</h2>
        <ul>
            <li><a href="PDSController_h/index.html">PDSController</a> - Main PDS controller</li>
            <li><a href="PDSDatabase_h/index.html">PDSDatabase</a> - Database layer</li>
        </ul>
    </div>
    
    <div class="category">
        <h2>Repository Layer</h2>
        <ul>
            <li><a href="MST_h/index.html">MST</a> - Merkle Search Tree</li>
            <li><a href="CAR_h/index.html">CAR</a> - Content Addressable Records</li>
        </ul>
    </div>
    
    <div class="category">
        <h2>Authentication</h2>
        <ul>
            <li><a href="Session_h/index.html">Session</a> - Session management</li>
            <li><a href="OAuth2_h/index.html">OAuth2</a> - OAuth 2.0 implementation</li>
            <li><a href="JWT_h/index.html">JWT</a> - JWT token handling</li>
        </ul>
    </div>
    
    <div class="category">
        <h2>Network Layer</h2>
        <ul>
            <li><a href="HttpServer_h/index.html">HttpServer</a> - HTTP server</li>
            <li><a href="XrpcHandler_h/index.html">XrpcHandler</a> - XRPC protocol handler</li>
            <li><a href="XrpcMethodRegistry_h/index.html">XrpcMethodRegistry</a> - Method registration</li>
        </ul>
    </div>
    
    <div class="category">
        <h2>Admin & Tools</h2>
        <ul>
            <li><a href="PDSMetrics_h/index.html">PDSMetrics</a> - Prometheus metrics</li>
            <li><a href="PDSAdminAuth_h/index.html">PDSAdminAuth</a> - Admin authentication</li>
            <li><a href="PDSAdminHandler_h/index.html">PDSAdminHandler</a> - Admin endpoints</li>
            <li><a href="PDSLogger_h/index.html">PDSLogger</a> - Structured logging</li>
            <li><a href="PDSCLIDefinitions_h/index.html">PDSCLIDefinitions</a> - CLI framework</li>
        </ul>
    </div>
    
    <hr>
    <p><small>Generated with HeaderDoc</small></p>
</body>
</html>
HTML

echo ""
echo "Documentation generated successfully!"
echo "Output: $OUTPUT_DIR"
echo ""
echo "To view documentation:"
echo "  open $OUTPUT_DIR/index.html"

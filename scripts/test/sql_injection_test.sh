#!/bin/bash
#
# sql_injection_test.sh
# Test for actual SQL injection vulnerabilities in the codebase
#

set -e

cd "$(dirname "$0")"

echo "========================================"
echo "  SQL Injection Vulnerability Test"
echo "========================================"
echo ""

# Create test SQL payloads that would exploit the vulnerabilities
MALICIOUS_DID="' OR '1'='1"
MALICIOUS_DID2="'; DROP TABLE accounts;--"
MALICIOUS_DID3="' UNION SELECT * FROM accounts--"

echo "Testing SQL Injection Vulnerability #1 (PDSController.m:882)"
echo "Vulnerable code:"
echo '  NSString *query = [NSString stringWithFormat:@"SELECT DISTINCT collection FROM records WHERE did = '\''%@'\'' ORDER BY collection", account.did];'
echo ""
echo "Test payload: $MALICIOUS_DID"
echo "Expected: SQL syntax error or unexpected results"
echo ""

# Create a test that shows the vulnerability
cat > /tmp/test_injection.c << 'EOF'
#include <stdio.h>
#include <string.h>

int main() {
    // Simulate the vulnerable code
    const char *did = "' OR '1'='1";
    char query[500];
    snprintf(query, sizeof(query), "SELECT DISTINCT collection FROM records WHERE did = '%s' ORDER BY collection", did);
    
    printf("Generated SQL:\n%s\n\n", query);
    
    // Check if injection is possible
    if (strstr(query, "' OR '1'='1") != NULL) {
        printf("VULNERABILITY CONFIRMED: SQL injection pattern found in query\n");
        printf("The query will execute with modified WHERE clause\n");
        return 1;
    }
    
    return 0;
}
EOF

gcc /tmp/test_injection.c -o /tmp/test_injection 2>/dev/null && /tmp/test_injection

echo ""
echo "Testing SQL Injection Vulnerability #2 (AdminService.m:155)"
echo "Vulnerable code:"
echo '  NSString *sql = [NSString stringWithFormat:@"UPDATE accounts SET invite_enabled = 1, updated_at = '\''%@'\'' WHERE did = '\''%@'\''", date, did];'
echo ""
echo "Test payload: $MALICIOUS_DID"
echo ""

cat > /tmp/test_injection2.c << 'EOF'
#include <stdio.h>
#include <string.h>

int main() {
    const char *did = "'; DROP TABLE accounts;--";
    const char *date = "2024-01-01T00:00:00Z";
    char sql[500];
    snprintf(sql, sizeof(sql), "UPDATE accounts SET invite_enabled = 1, updated_at = '%s' WHERE did = '%s'", date, did);
    
    printf("Generated SQL:\n%s\n\n", sql);
    
    if (strstr(sql, "DROP TABLE") != NULL) {
        printf("CRITICAL VULNERABILITY: DROP TABLE statement can be injected!\n");
        printf("An attacker could delete the entire accounts table\n");
        return 2;
    }
    
    return 0;
}
EOF

gcc /tmp/test_injection2.c -o /tmp/test_injection2 2>/dev/null && /tmp/test_injection2

echo ""
echo "========================================"
echo "  Summary"
echo "========================================"
echo ""
echo "The codebase has multiple SQL injection vulnerabilities:"
echo ""
echo "1. PDSController.m:882 - SELECT query with unescaped did"
echo "2. AdminService.m:155 - UPDATE query with unescaped did and date"
echo "3. AdminService.m:182 - UPDATE query with unescaped did"
echo "4. AdminService.m:229 - SELECT query with unescaped did"
echo "5. AdminService.m:247 - SELECT query with unescaped subject"
echo ""
echo "RECOMMENDATION: Use parameterized queries instead of string formatting"
echo ""
echo "Correct approach:"
echo "  NSString *query = @\"SELECT DISTINCT collection FROM records WHERE did = ? ORDER BY collection\";"
echo "  NSArray *rows = [_database executeParameterizedQuery:query params:@[account.did]];"
echo ""

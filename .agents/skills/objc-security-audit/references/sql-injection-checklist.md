# SQL Injection Checklist

Use this checklist while validating candidates from `scan_sql_injection.sh`.

## String formatting in SQL
- Verify `%@` placeholders in SQL strings are NOT user input.
- Check if formatted values come from request parameters, JSON body, or URL.
- Trace data flow from source to SQL execution.
- Verify parameterized queries are used instead of string formatting.

## Dynamic SQL construction
- Verify table names are whitelisted, not user-provided.
- Verify column names in ORDER BY, SELECT are validated.
- Verify no user input in LIMIT, OFFSET without validation.
- Check for indirect injection via config files or environment.

## Execution patterns
- `sqlite3_exec` with formatted strings = HIGH RISK.
- `sqlite3_prepare` + `sqlite3_bind_*` = SAFE pattern.
- String concatenation before prepare = REVIEW REQUIRED.
- Check all error paths for partial SQL leakage.

## Common injection patterns to check
```objc
// VULNERABLE: Direct user input in SQL
NSString *sql = [NSString stringWithFormat:@"SELECT * FROM users WHERE id = '%@'", userId];

// SAFE: Parameterized query
sqlite3_prepare_v2(db, "SELECT * FROM users WHERE id = ?", -1, &stmt, NULL);
sqlite3_bind_text(stmt, 1, [userId UTF8String], -1, SQLITE_TRANSIENT);

// VULNERABLE: Dynamic table name
NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@", tableName];

// SAFE: Whitelisted table name
NSSet *allowedTables = [NSSet setWithObjects:@"users", @"posts", nil];
if (![allowedTables containsObject:tableName]) { return error; }
NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@", tableName];
```

## Input validation
- Apply `PDSInputValidator` before any SQL context.
- Validate type, length, and format of inputs.
- Reject known SQL keywords in user input (defense in depth).
- Log suspicious input patterns for monitoring.

## Testing recommendations
- Test with SQL metacharacters: `'`, `"`, `;`, `--`, `/*`, `*/`.
- Test with boolean conditions: `' OR '1'='1`, `' OR 1=1--`.
- Test with UNION-based injection attempts.
- Test with time-based blind injection: `'; WAITFOR DELAY '0:0:5'--`.
- Use fuzzing corpus with injection patterns.

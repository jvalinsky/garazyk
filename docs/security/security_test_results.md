# Security Test Results

**Generated:** 2026-01-09 03:45:30 UTC
**Commit:** ca8aeef6d4f4e3ed293bd87d8c04ff08f42f814a

## Summary

| Category | Tests | Passed | Failed |
|----------|-------|--------|--------|
| CBOR Payloads | 23 | 23 | 0 |
| HTTP Payloads | 17 | 17 | 0 |
| XRPC Payloads | 12 | 12 | 0 |
| SQL Payloads | 10 | 10 | 0 |
| Fuzzer Tests | 4 | 4 | 0 |
| **Total** | **66** | **66** | **0** |

## CBOR Security Tests

### CBOR Test Cases
- **cbor_array_overflow**: 3 bytes
- **cbor_break_only**: 1 bytes
- **cbor_byte_overflow**: 2 bytes
- **cbor_empty_array**: 1 bytes
- **cbor_empty_map**: 1 bytes
- **cbor_indefinite_array**: 1 bytes
- **cbor_indefinite_string**: 1 bytes
- **cbor_map_overflow**: 1 bytes
- **cbor_negative_overflow**: 9 bytes
- **cbor_negint_neg1**: 1 bytes
- **cbor_nested_array**: 10 bytes
- **cbor_nested_map**: 10 bytes
- **cbor_overflow_integer**: 9 bytes
- **cbor_simple_value_invalid**: 1 bytes
- **cbor_string_a**: 2 bytes
- **cbor_string_hello**: 6 bytes
- **cbor_string_helloworld**: 11 bytes
- **cbor_string_overflow**: 2 bytes
- **cbor_tag_0_date**: 1 bytes
- **cbor_uint_0**: 1 bytes
- **cbor_uint16_overflow**: 4 bytes
- **cbor_uint32_overflow**: 6 bytes
- **cbor_uint8_overflow**: 3 bytes

## HTTP Security Tests

### HTTP Test Cases
- **http_admin_bypass**: 62 bytes
- **http_chunked_encoding**: 58 bytes
- **http_expect_100**: 49 bytes
- **http_header_injection**: 78 bytes
- **http_huge_content_length**: 74 bytes
- **http_negative_content_length**: 56 bytes
- **http_nonstandard_method**: 33 bytes
- **http_null_byte**: 38 bytes
- **http_null_in_path**: 65 bytes
- **http_null_method**: 31 bytes
- **http_overflow_limit**: 53 bytes
- **http_path_traversal_1**: 52 bytes
- **http_path_traversal_2**: 51 bytes
- **http_path_traversal_3**: 51 bytes
- **http_sql_injection_param**: 67 bytes
- **http_xrpc_create_session**: 196 bytes
- **http_xrpc_get_session**: 263 bytes

## XRPC Security Tests

### XRPC Test Cases
- **xrpc_admin_bypass**: 62 bytes
- **xrpc_create_record**: 329 bytes
- **xrpc_get_profile**: 119 bytes
- **xrpc_get_timeline**: 122 bytes
- **xrpc_list_records**: 164 bytes
- **xrpc_negative_content_length**: 118 bytes
- **xrpc_nsid_injection**: 64 bytes
- **xrpc_null_method**: 65 bytes
- **xrpc_overflow_cursor**: 10068 bytes
- **xrpc_overflow_limit**: 77 bytes
- **xrpc_refresh_session**: 174 bytes
- **xrpc_valid_create**: 213 bytes

## SQL Injection Tests

### SQL Injection Test Cases
- **sql_and_true**: 12 bytes
- **sql_attach_db**: 45 bytes
- **sql_concat**: 23 bytes
- **sql_drop_table**: 22 bytes
- **sql_load_ext**: 49 bytes
- **sql_or_1eq1**: 11 bytes
- **sql_or_true**: 15 bytes
- **sql_order_by**: 32 bytes
- **sql_stacked**: 23 bytes
- **sql_union_1**: 30 bytes

## Crashes Detected

- No crashes detected

## Recommendations

- All tests passed - code handles malicious payloads correctly
- Continue fuzzing with longer runs for additional coverage

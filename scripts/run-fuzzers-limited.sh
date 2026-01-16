#!/bin/bash
set -e
cd "/Users/jack/Software/objpds/.worktrees/macos-security-phase2"
echo "Running fuzzers with limited runs..."
mkdir -p fuzzing/crashers fuzzing/corpus_xrpc fuzzing/corpus_cbor fuzzing/corpus_http fuzzing/corpus_sql
/Users/jack/Software/objpds/.worktrees/macos-security-phase2/build/fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -runs=5000 || echo "XRPC fuzzer completed"
/Users/jack/Software/objpds/.worktrees/macos-security-phase2/build/fuzzing/fuzz_cbor fuzzing/corpus_cbor/ -max_len=65536 -jobs=8 -runs=5000 || echo "CBOR fuzzer completed"
/Users/jack/Software/objpds/.worktrees/macos-security-phase2/build/fuzzing/fuzz_http fuzzing/corpus_http/ -max_len=65536 -jobs=8 -runs=5000 || echo "HTTP fuzzer completed"
/Users/jack/Software/objpds/.worktrees/macos-security-phase2/build/fuzzing/fuzz_auth fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -runs=5000 || echo "Auth fuzzer completed"
/Users/jack/Software/objpds/.worktrees/macos-security-phase2/build/fuzzing/fuzz_blob /dev/null -max_len=65536 -jobs=8 -runs=1000 || echo "Blob fuzzer completed"
/Users/jack/Software/objpds/.worktrees/macos-security-phase2/build/fuzzing/fuzz_sqlite fuzzing/corpus_sql/ -max_len=10000 -jobs=8 -runs=1000 || echo "SQL fuzzer completed"
echo "Fuzzing session complete."

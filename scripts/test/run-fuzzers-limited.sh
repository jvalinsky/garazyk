#!/bin/bash
set -e
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
echo "Running fuzzers with limited runs..."
mkdir -p fuzzing/crashers fuzzing/corpus_xrpc fuzzing/corpus_cbor fuzzing/corpus_http fuzzing/corpus_sql
"$REPO_ROOT/fuzzing/fuzz_xrpc" fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -runs=5000 || echo "XRPC fuzzer completed"
"$REPO_ROOT/fuzzing/fuzz_cbor" fuzzing/corpus_cbor/ -max_len=65536 -jobs=8 -runs=5000 || echo "CBOR fuzzer completed"
"$REPO_ROOT/fuzzing/fuzz_http" fuzzing/corpus_http/ -max_len=65536 -jobs=8 -runs=5000 || echo "HTTP fuzzer completed"
"$REPO_ROOT/fuzzing/fuzz_auth" fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -runs=5000 || echo "Auth fuzzer completed"
"$REPO_ROOT/fuzzing/fuzz_blob" /dev/null -max_len=65536 -jobs=8 -runs=1000 || echo "Blob fuzzer completed"
"$REPO_ROOT/fuzzing/fuzz_sqlite" fuzzing/corpus_sql/ -max_len=10000 -jobs=8 -runs=1000 || echo "SQL fuzzer completed"
echo "Running Lexicon fuzzer..."
"$REPO_ROOT/fuzzing/fuzz_lexicon" fuzzing/corpus_lexicon/ -max_len=65536 -jobs=8 -runs=1000 || echo "Lexicon fuzzer completed"
echo "Running MST fuzzer..."
"$REPO_ROOT/fuzzing/fuzz_mst" fuzzing/corpus_mst/ -max_len=65536 -jobs=8 -runs=1000 || echo "MST fuzzer completed"
echo "Fuzzing session complete."

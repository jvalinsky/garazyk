#!/bin/bash
set -e
cd "/Users/jack/Software/objpds"
echo "Running comprehensive fuzzing session..."
mkdir -p fuzzing/crashers fuzzing/corpus_xrpc fuzzing/corpus_cbor fuzzing/corpus_http fuzzing/corpus_sql fuzzing/corpus_lexicon fuzzing/corpus_mst
echo "Running XRPC fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/objpds/build/fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running CBOR fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/objpds/build/fuzzing/fuzz_cbor fuzzing/corpus_cbor/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running HTTP fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/objpds/build/fuzzing/fuzz_http fuzzing/corpus_http/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running Auth fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/objpds/build/fuzzing/fuzz_auth fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running Blob fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/objpds/build/fuzzing/fuzz_blob /dev/null -max_len=50000000 -jobs=4 -timeout=10 || true
echo "Running SQL fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/objpds/build/fuzzing/fuzz_sqlite fuzzing/corpus_sql/ -max_len=10000 -jobs=4 -timeout=10 || true
echo "Running Lexicon fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/objpds/build/fuzzing/fuzz_lexicon fuzzing/corpus_lexicon/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running MST fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/objpds/build/fuzzing/fuzz_mst fuzzing/corpus_mst/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Comprehensive fuzzing session complete."
ls -la fuzzing/crashers/ 2>/dev/null || echo "No crashes detected"

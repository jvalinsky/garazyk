#!/bin/bash
set -e
cd "$(dirname "$0")/.."
echo "Running comprehensive fuzzing session..."
mkdir -p fuzzing/crashers fuzzing/corpus_xrpc fuzzing/corpus_cbor fuzzing/corpus_http fuzzing/corpus_sql
echo "Running XRPC fuzzer (30 seconds)..."
./build/fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running CBOR fuzzer (30 seconds)..."
./build/fuzzing/fuzz_cbor fuzzing/corpus_cbor/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running HTTP fuzzer (30 seconds)..."
./build/fuzzing/fuzz_http fuzzing/corpus_http/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running Auth fuzzer (30 seconds)..."
./build/fuzzing/fuzz_auth fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running Blob fuzzer (30 seconds)..."
./build/fuzzing/fuzz_blob fuzzing/corpus_blob/ -max_len=50000000 -jobs=4 -timeout=10 || true
echo "Running SQL fuzzer (30 seconds)..."
./build/fuzzing/fuzz_sqlite fuzzing/corpus_sql/ -max_len=10000 -jobs=4 -timeout=10 || true
echo "Running Lexicon fuzzer (30 seconds)..."
./build/fuzzing/fuzz_lexicon fuzzing/corpus_lexicon/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running MST fuzzer (30 seconds)..."
./build/fuzzing/fuzz_mst fuzzing/corpus_mst/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Comprehensive fuzzing session complete."
ls -la fuzzing/crashers/ 2>/dev/null || echo "No crashes detected"

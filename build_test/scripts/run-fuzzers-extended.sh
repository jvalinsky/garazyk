#!/bin/bash
set -e
cd "/Users/jack/Software/garazyk"
echo "Running comprehensive fuzzing session..."
mkdir -p fuzzing/crashers fuzzing/corpus/{xrpc,cbor,http,auth,blob,sql,lexicon,mst}
echo "Running XRPC fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/garazyk/build_test/fuzzing/fuzz_xrpc fuzzing/corpus/xrpc/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running CBOR fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/garazyk/build_test/fuzzing/fuzz_cbor fuzzing/corpus/cbor/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running HTTP fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/garazyk/build_test/fuzzing/fuzz_http fuzzing/corpus/http/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running JWT fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/garazyk/build_test/fuzzing/fuzz_jwt fuzzing/corpus/auth/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running DPoP fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/garazyk/build_test/fuzzing/fuzz_dpop fuzzing/corpus/auth/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running MIME fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/garazyk/build_test/fuzzing/fuzz_mime fuzzing/corpus/blob/ -max_len=65536 -jobs=4 -timeout=10 || true
echo "Running SQLite fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/garazyk/build_test/fuzzing/fuzz_sqlite fuzzing/corpus/sql/ -max_len=10000 -jobs=4 -timeout=10 || true
echo "Running Lexicon fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/garazyk/build_test/fuzzing/fuzz_lexicon fuzzing/corpus/lexicon/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Running MST fuzzer (30 seconds)..."
timeout 30 /Users/jack/Software/garazyk/build_test/fuzzing/fuzz_mst fuzzing/corpus/mst/ -max_len=65536 -jobs=8 -timeout=10 || true
echo "Comprehensive fuzzing session complete."
ls -la fuzzing/crashers/ 2>/dev/null || echo "No crashes detected"

#!/bin/bash
set -e
cd "/Users/jack/Software/garazyk"
echo "Running fuzzers with limited runs..."
mkdir -p fuzzing/crashers fuzzing/corpus/{xrpc,cbor,http,auth,blob,sql,lexicon,mst}
/Users/jack/Software/garazyk/build_test/fuzzing/fuzz_xrpc fuzzing/corpus/xrpc/ -max_len=65536 -jobs=8 -runs=5000 || echo "XRPC fuzzer completed"
/Users/jack/Software/garazyk/build_test/fuzzing/fuzz_cbor fuzzing/corpus/cbor/ -max_len=65536 -jobs=8 -runs=5000 || echo "CBOR fuzzer completed"
/Users/jack/Software/garazyk/build_test/fuzzing/fuzz_http fuzzing/corpus/http/ -max_len=65536 -jobs=8 -runs=5000 || echo "HTTP fuzzer completed"
/Users/jack/Software/garazyk/build_test/fuzzing/fuzz_jwt fuzzing/corpus/auth/ -max_len=65536 -jobs=8 -runs=5000 || echo "JWT fuzzer completed"
/Users/jack/Software/garazyk/build_test/fuzzing/fuzz_dpop fuzzing/corpus/auth/ -max_len=65536 -jobs=8 -runs=5000 || echo "DPoP fuzzer completed"
/Users/jack/Software/garazyk/build_test/fuzzing/fuzz_mime fuzzing/corpus/blob/ -max_len=65536 -jobs=8 -runs=1000 || echo "MIME fuzzer completed"
/Users/jack/Software/garazyk/build_test/fuzzing/fuzz_sqlite fuzzing/corpus/sql/ -max_len=10000 -jobs=8 -runs=1000 || echo "SQLite fuzzer completed"
/Users/jack/Software/garazyk/build_test/fuzzing/fuzz_lexicon fuzzing/corpus/lexicon/ -max_len=65536 -jobs=8 -runs=1000 || echo "Lexicon fuzzer completed"
/Users/jack/Software/garazyk/build_test/fuzzing/fuzz_mst fuzzing/corpus/mst/ -max_len=65536 -jobs=8 -runs=1000 || echo "MST fuzzer completed"
echo "Fuzzing session complete."

# CMake generated Testfile for 
# Source directory: /Users/jack/Software/garazyk/secp256k1/src
# Build directory: /Users/jack/Software/garazyk/build_test/secp256k1/src
# 
# This file includes the relevant testing commands required for 
# testing this directory and lists subdirectories to be tested as well.
include("/Users/jack/Software/garazyk/build_test/secp256k1/src/noverify_tests_include.cmake")
include("/Users/jack/Software/garazyk/build_test/secp256k1/src/tests_include.cmake")
add_test([=[secp256k1.exhaustive_tests]=] "/Users/jack/Software/garazyk/build_test/secp256k1/bin/exhaustive_tests")
set_tests_properties([=[secp256k1.exhaustive_tests]=] PROPERTIES  LABELS "secp256k1_exhaustive" _BACKTRACE_TRIPLES "/Users/jack/Software/garazyk/secp256k1/src/CMakeLists.txt;174;add_test;/Users/jack/Software/garazyk/secp256k1/src/CMakeLists.txt;0;")

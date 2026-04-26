# CMake generated Testfile for 
# Source directory: /Users/jack/Software/garazyk/secp256k1/src
# Build directory: /Users/jack/Software/garazyk/build_test/secp256k1/src
# 
# This file includes the relevant testing commands required for 
# testing this directory and lists subdirectories to be tested as well.
add_test([=[secp256k1_noverify_tests]=] "/Users/jack/Software/garazyk/build_test/secp256k1/bin/noverify_tests")
set_tests_properties([=[secp256k1_noverify_tests]=] PROPERTIES  _BACKTRACE_TRIPLES "/Users/jack/Software/garazyk/secp256k1/src/CMakeLists.txt;150;add_test;/Users/jack/Software/garazyk/secp256k1/src/CMakeLists.txt;0;")
add_test([=[secp256k1_tests]=] "/Users/jack/Software/garazyk/build_test/secp256k1/bin/tests")
set_tests_properties([=[secp256k1_tests]=] PROPERTIES  _BACKTRACE_TRIPLES "/Users/jack/Software/garazyk/secp256k1/src/CMakeLists.txt;155;add_test;/Users/jack/Software/garazyk/secp256k1/src/CMakeLists.txt;0;")
add_test([=[secp256k1_exhaustive_tests]=] "/Users/jack/Software/garazyk/build_test/secp256k1/bin/exhaustive_tests")
set_tests_properties([=[secp256k1_exhaustive_tests]=] PROPERTIES  _BACKTRACE_TRIPLES "/Users/jack/Software/garazyk/secp256k1/src/CMakeLists.txt;165;add_test;/Users/jack/Software/garazyk/secp256k1/src/CMakeLists.txt;0;")

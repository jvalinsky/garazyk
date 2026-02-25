# CMake generated Testfile for 
# Source directory: /Users/jack/Software/garazyk
# Build directory: /Users/jack/Software/garazyk/build_local
# 
# This file includes the relevant testing commands required for 
# testing this directory and lists subdirectories to be tested as well.
add_test([=[AllTests]=] "/Users/jack/Software/garazyk/build_local/tests/AllTests")
set_tests_properties([=[AllTests]=] PROPERTIES  _BACKTRACE_TRIPLES "/Users/jack/Software/garazyk/CMakeLists.txt;458;add_test;/Users/jack/Software/garazyk/CMakeLists.txt;0;")
subdirs("secp256k1")

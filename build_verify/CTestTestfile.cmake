# CMake generated Testfile for 
# Source directory: /Users/jack/Software/objpds
# Build directory: /Users/jack/Software/objpds/build_verify
# 
# This file includes the relevant testing commands required for 
# testing this directory and lists subdirectories to be tested as well.
add_test([=[AllTests]=] "/Users/jack/Software/objpds/build_verify/tests/AllTests")
set_tests_properties([=[AllTests]=] PROPERTIES  _BACKTRACE_TRIPLES "/Users/jack/Software/objpds/CMakeLists.txt;304;add_test;/Users/jack/Software/objpds/CMakeLists.txt;0;")
subdirs("secp256k1")

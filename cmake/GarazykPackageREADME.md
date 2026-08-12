# Garazyk experimental CMake package (0.x)

Install with `-DGARAZYK_INSTALL=ON`, then consume from another project:

```cmake
find_package(Garazyk 0.1 REQUIRED)
target_link_libraries(my_app PRIVATE Garazyk::ATProtoCore)
```

Public headers preserve the in-tree layout under `include/garazyk/Sources` and
`include/garazyk/Frameworks`. Import paths such as `#import "Core/CID.h"` and
umbrella headers under `Frameworks/ATProtoCore/ATProtoCore.h` work when both
roots are on the include path (the generated config sets this on exported
targets).

Static archives require platform link flags (`-ObjC` on Apple toolchains when
pulling in Objective-C categories). When Garazyk was built with OpenSSL enabled,
consumers must also find OpenSSL (set `OPENSSL_ROOT_DIR` on macOS if needed).

This package ships source-built static libraries only; API stability is not promised at 0.x.

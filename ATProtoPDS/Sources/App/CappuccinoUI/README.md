# CappuccinoUI

Objective-J/Cappuccino workspace for the in-progress web GUI rewrite.

## Build

From repo root:

```bash
./scripts/build_cappuccino_ui.sh
```

This will:

1. Install npm dependencies in this directory.
2. Generate Cappuccino `Frameworks/` if missing.
3. Build the app with `jake release`.
4. Stage output at `ATProtoPDS/Sources/App/CappuccinoUI/dist/CappuccinoUI`.

## CMake integration

Frontend build is opt-in from CMake:

```bash
cmake -S . -B build -DBUILD_CAPPUCCINO_UI=ON
cmake --build build --target cappuccino-ui-build
```

#!/bin/bash
set -e

echo "=== 1. Compiling C++ Audio DSP Engine ==="
clang++ -O3 -std=c++17 -shared -fPIC \
  -framework AudioToolbox -framework CoreFoundation \
  native/audio_processor.cpp native/ffi_bridge.cpp \
  -o libviolin_engine.dylib

echo "✓ libviolin_engine.dylib built successfully"

# If macos app bundle exists, copy dylib inside
if [ -d "build/macos/Build/Products/Debug/easy_violin.app/Contents" ]; then
  mkdir -p build/macos/Build/Products/Debug/easy_violin.app/Contents/Frameworks
  cp libviolin_engine.dylib build/macos/Build/Products/Debug/easy_violin.app/Contents/Frameworks/
  cp libviolin_engine.dylib build/macos/Build/Products/Debug/
  echo "✓ Copied dylib to macOS app bundle"
fi

echo "=== 2. Running Flutter Tests ==="
/Users/user/Downloads/flutter/bin/flutter test

echo "=== All checks passed! Ready to run: flutter run -d macos ==="

#!/bin/bash
# Pure source compile/link check: no app bundle, framework copying or signing.
set -euo pipefail
cd "$(dirname "$0")"
[[ $# == 1 ]] || { echo 'Usage: bash compile-source.sh NEW_OUTPUT_DIRECTORY' >&2; exit 64; }
mkdir "$1" || { echo '拒绝覆盖已存在的源码编译目录。' >&2; exit 1; }
compile_dir=$(cd "$1" && pwd)
/usr/bin/xcrun clang -arch arm64 -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.4 \
    -c TCSession.c -o "$compile_dir/TCSession.o"
for source in TCLifecyclePolicy; do
    /usr/bin/xcrun clang -arch arm64 -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.4 \
        -c "$source.c" -o "$compile_dir/$source.o"
done
for source in main TCWorker TCOCR TCImageAnalysis TCImageTranslation TCLifecycleAgent; do
    /usr/bin/xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter \
        -mmacosx-version-min=14.4 -c "$source.m" -o "$compile_dir/$source.o"
done
/usr/bin/xcrun clang -arch arm64 -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter \
    -mmacosx-version-min=14.4 TCImageOCRHelper.m "$compile_dir/TCImageTranslation.o" \
    -framework Cocoa -framework Vision -framework ImageIO -framework CoreText -framework UniformTypeIdentifiers \
    -o "$compile_dir/BroOCRHelper"
/usr/bin/xcrun swiftc -target arm64-apple-macosx14.4 -O -warnings-as-errors -parse-as-library \
    -module-name TCTranslation -module-cache-path "$compile_dir/module-cache" \
    -import-objc-header TCImageTranslation.h TCTranslation.swift TCImageTranslation.swift "$compile_dir/main.o" "$compile_dir/TCWorker.o" "$compile_dir/TCOCR.o" "$compile_dir/TCImageAnalysis.o" "$compile_dir/TCImageTranslation.o" "$compile_dir/TCLifecycleAgent.o" "$compile_dir/TCLifecyclePolicy.o" "$compile_dir/TCSession.o" \
    -framework Cocoa -framework Carbon -framework Vision -framework ServiceManagement \
    -framework ScreenCaptureKit -framework ImageIO -framework CoreText -framework UniformTypeIdentifiers -framework Translation -framework SwiftUI \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -o "$compile_dir/TencentCapture.compile-check"
echo "$compile_dir/TencentCapture.compile-check"

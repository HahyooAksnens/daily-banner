#!/bin/zsh
set -eu
cd "${0:A:h}"
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
mkdir -p .build/module-cache 每日一句.app/Contents/MacOS
swiftc -O -module-cache-path .build/module-cache -framework AppKit Sources/main.swift -o 每日一句.app/Contents/MacOS/DailyBanner
xattr -d com.apple.FinderInfo 每日一句.app 2>/dev/null || true
codesign --force --sign - 每日一句.app

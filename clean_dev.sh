cat << 'EOF' > ~/clean_dev.sh
#!/bin/bash

echo "🧹 Starting macOS Developer & System Cleanup..."
echo "------------------------------------------------"

# 1. Clear Xcode DerivedData
if [ -d ~/Library/Developer/Xcode/DerivedData ]; then
    echo "🗑️ Clearing Xcode DerivedData..."
    rm -rf ~/Library/Developer/Xcode/DerivedData/*
fi

# 2. Clear iOS Simulator Devices & Runtimes
echo "📱 Erasing iOS Simulators..."
xcrun simctl erase all 2>/dev/null
xcrun simctl runtime delete all 2>/dev/null
rm -rf ~/Library/Developer/CoreSimulator/Devices/* 2>/dev/null

# 3. Clear CocoaPods, Swift Package Manager & Conda Caches
echo "📦 Clearing Package Manager Caches..."
rm -rf ~/Library/Caches/org.swift.swiftpm 2>/dev/null
rm -rf ~/Library/Caches/CocoaPods 2>/dev/null
if command -v conda &> /dev/null; then
    conda clean --all -y 2>/dev/null
fi

# 4. Clear Arduino Caches
echo "🤖 Clearing Arduino Staging & Caches..."
rm -rf ~/Library/Arduino15/staging/* 2>/dev/null
rm -rf ~/Library/Arduino15/cache/* 2>/dev/null

# 5. Clear User Caches & Trash
echo "🗂️ Clearing User Caches & Trash..."
rm -rf ~/Library/Caches/* 2>/dev/null
rm -rf ~/.Trash/* 2>/dev/null

# 6. Sideloadly Clean Reset
echo "📱 Cleaning Sideloadly Temporary Database..."
rm -rf ~/.sideloadly ~/Library/Application\ Support/sideloadly
mkdir -p ~/.sideloadly ~/Library/Application\ Support/sideloadly

echo "------------------------------------------------"
echo "✅ Cleanup Complete! Current Available Space:"
df -h / | awk 'NR==2 {print $4}'
EOF

#!/usr/bin/env bash
set -euo pipefail
adb install -r dist/Sableen-android-universal.apk
adb shell am start -W -n com.example.sableen/.MainActivity | grep -F 'Status: ok'
trap 'adb logcat -d -s flutter:E AndroidRuntime:E' ERR
python3 tool/ci/android_playback.py

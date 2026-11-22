#!/usr/bin/env bash
set -euo pipefail
adb install -r dist/Sableen-android-universal.apk
# The system's first-use fullscreen tutorial covers the activity on fresh AVDs.
adb shell settings put secure immersive_mode_confirmations confirmed
adb shell am start -W -n com.example.sableen/.MainActivity | grep -F 'Status: ok'
trap 'adb logcat -d -s flutter:I AndroidRuntime:E MediaCodec:E | tail -n 80' ERR
/usr/bin/python3 tool/ci/android_playback.py --check-offline

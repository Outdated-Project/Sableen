#!/usr/bin/env bash
set -euo pipefail
adb install -r dist/Sableen-android-universal.apk
adb shell am start -W -n com.example.sableen/.MainActivity | grep -F 'Status: ok'
for attempt in $(seq 1 40); do
  adb shell uiautomator dump /data/local/tmp/sableen-window.xml >/dev/null
  if adb shell cat /data/local/tmp/sableen-window.xml | grep -F '梦笔不能停' >/dev/null; then
    adb shell pidof com.example.sableen
    exit 0
  fi
  sleep 2
done
adb logcat -d -s flutter:E AndroidRuntime:E
exit 1

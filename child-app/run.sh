#!/bin/bash
set -e

DEVICE="${1:-RZCY20K5J9J}"
PACKAGE="com.example.childapp"
ACTIVITY=".ui.MainActivity"

echo "=========================================="
echo " Starting Child App on device: $DEVICE"
echo "=========================================="

build_and_launch() {
    echo ""
    echo "⚡ Building and installing on $DEVICE..."
    ./gradlew assembleDebug -q
    adb -s "$DEVICE" install -r -d app/build/outputs/apk/debug/app-debug.apk
    
    echo "🚀 Launching $PACKAGE$ACTIVITY..."
    adb -s "$DEVICE" shell am force-stop "$PACKAGE"
    adb -s "$DEVICE" shell am start -n "$PACKAGE/$ACTIVITY"
    echo "✅ App is running on $DEVICE!"
}

# Initial build & launch
build_and_launch

echo ""
echo "---------------------------------------------------------"
echo " 🔥 Child App Interactive Console"
echo "  [r / Enter] : Hot Restart (Rebuild, reinstall & restart)"
echo "  [l]         : Show live logs (logcat)"
echo "  [q]         : Quit"
echo "---------------------------------------------------------"

while true; do
    read -r -p "Command ([r]estart, [l]ogs, [q]uit): " cmd
    case "$cmd" in
        ""|"r"|"R")
            build_and_launch
            ;;
        "l"|"L")
            echo "--- Streaming logs from $DEVICE (Ctrl+C to stop logs) ---"
            adb -s "$DEVICE" logcat -c
            adb -s "$DEVICE" logcat -v time -s ChildMonitoringService:V SocketManager:V ApiClient:V AmbientAudioService:V AmbientAudioWebRtcManager:V
            ;;
        "q"|"Q")
            echo "Exiting."
            exit 0
            ;;
        *)
            echo "Unknown option. Use 'r' to restart, 'l' for logs, or 'q' to quit."
            ;;
    esac
done

#!/bin/bash
set -e

# Target Waydroid Device
WAYDROID_IP="192.168.240.112"
WAYDROID_PORT="5555"
WAYDROID_DEVICE="${WAYDROID_IP}:${WAYDROID_PORT}"

# Target Fixed Location (Latitude, Longitude)
TARGET_LAT="24.962638"
TARGET_LON="91.868172"

echo "=========================================="
echo " Starting Parent App on Waydroid"
echo "=========================================="

# 1. Check if Waydroid session/container is running
if command -v waydroid &>/dev/null; then
    WD_STATUS=$(waydroid status 2>/dev/null || true)
    if ! echo "$WD_STATUS" | grep -q "Container:[[:space:]]*RUNNING"; then
        echo "⚠️  Waydroid container is not running. Starting Waydroid session..."
        waydroid session start &>/dev/null &
        sleep 3
    fi
    # Extract dynamic IP if available
    CURRENT_IP=$(echo "$WD_STATUS" | awk -F':\t' '/IP address:/ {print $2}' | tr -d '[:space:]')
    if [ -n "$CURRENT_IP" ]; then
        WAYDROID_DEVICE="${CURRENT_IP}:${WAYDROID_PORT}"
    fi
fi

# 2. Check ADB connection to Waydroid
if ! adb devices | grep -q "${WAYDROID_DEVICE}[[:space:]]*device"; then
    echo "🔌 Connecting ADB to Waydroid (${WAYDROID_DEVICE})..."
    waydroid adb connect &>/dev/null || adb connect "${WAYDROID_DEVICE}" &>/dev/null || true
    sleep 1

    # If unauthorized or offline, attempt reconnect
    if adb devices | grep -q "${WAYDROID_DEVICE}[[:space:]]*unauthorized"; then
        echo "🔄 Reconnecting ADB..."
        adb -s "${WAYDROID_DEVICE}" reconnect &>/dev/null || true
        sleep 1
    fi
fi

# 3. Final verification of device
if ! adb devices | grep -q "${WAYDROID_DEVICE}[[:space:]]*device"; then
    ANY_WD=$(adb devices | grep -E "192\.168\.[0-9]+\.[0-9]+:5555[[:space:]]+device" | awk '{print $1}' | head -n1)
    if [ -n "$ANY_WD" ]; then
        WAYDROID_DEVICE="$ANY_WD"
    fi
fi

# 4. Set Fixed GPS & Network Location in Waydroid
if adb devices | grep -q "${WAYDROID_DEVICE}[[:space:]]*device"; then
    echo "📍 Locking Waydroid Location to: ${TARGET_LAT}, ${TARGET_LON}..."
    adb -s "$WAYDROID_DEVICE" shell "
        cmd location set-location-enabled true 2>/dev/null
        cmd location providers add-test-provider gps --requiresSatellite --supportsAltitude --supportsSpeed --supportsBearing 2>/dev/null || true
        cmd location providers set-test-provider-enabled gps true 2>/dev/null
        cmd location providers set-test-provider-location gps --location ${TARGET_LAT},${TARGET_LON} --accuracy 5 2>/dev/null || true

        cmd location providers add-test-provider network --requiresNetwork --supportsAltitude 2>/dev/null || true
        cmd location providers set-test-provider-enabled network true 2>/dev/null
        cmd location providers set-test-provider-location network --location ${TARGET_LAT},${TARGET_LON} --accuracy 5 2>/dev/null || true

        cmd location providers add-test-provider fused --supportsAltitude --supportsSpeed --supportsBearing 2>/dev/null || true
        cmd location providers set-test-provider-enabled fused true 2>/dev/null
        cmd location providers set-test-provider-location fused --location ${TARGET_LAT},${TARGET_LON} --accuracy 5 2>/dev/null || true
    " 2>/dev/null || true
    echo "✅ Location locked successfully!"
fi

echo "📱 Target Device: $WAYDROID_DEVICE"
echo "🚀 Launching flutter run..."
echo "---------------------------------------------------------"
echo " 🔥 Hot Reload & Restart:"
echo "  [r]         : Hot Reload"
echo "  [R / Shift+r]: Hot Restart"
echo "  [q]         : Quit"
echo "---------------------------------------------------------"

flutter run -d "$WAYDROID_DEVICE" "$@"

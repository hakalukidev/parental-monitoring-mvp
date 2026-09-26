#!/bin/bash
# Fixed GPS Location Script for Waydroid Emulator
# Sets permanent location to WR8J+VQ Sylhet, Bangladesh (Lat: 24.8975, Lon: 91.8705)

WAYDROID_IP="192.168.240.112:5555"
LAT="24.8975"
LON="91.8705"
ACCURACY="3.0"

echo "[Waydroid Location] Connecting to Waydroid at $WAYDROID_IP..."
adb connect "$WAYDROID_IP" >/dev/null 2>&1

adb -s "$WAYDROID_IP" shell "
  cmd location set-location-enabled true
  cmd location providers add-test-provider gps --requiresSatellite --supportsAltitude --supportsSpeed --supportsBearing
  cmd location providers set-test-provider-enabled gps true
  cmd location providers add-test-provider network --requiresNetwork --supportsAltitude
  cmd location providers set-test-provider-enabled network true
  cmd location providers add-test-provider fused --supportsAltitude --supportsSpeed --supportsBearing
  cmd location providers set-test-provider-enabled fused true
" >/dev/null 2>&1

echo "[Waydroid Location] Fixed location set to Sylhet ($LAT, $LON). Keeping alive..."

while true; do
  adb -s "$WAYDROID_IP" shell "
    cmd location providers set-test-provider-location gps --location $LAT,$LON --accuracy $ACCURACY
    cmd location providers set-test-provider-location network --location $LAT,$LON --accuracy $ACCURACY
    cmd location providers set-test-provider-location fused --location $LAT,$LON --accuracy $ACCURACY
  " >/dev/null 2>&1
  sleep 3
done

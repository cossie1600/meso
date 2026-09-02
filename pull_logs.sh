#!/bin/bash

BUNDLE_ID="com.cg.MesoSensorDashboard.32SKC6LW32"
DEVICE_UUID="0A328CF2-996F-5C4A-BA30-079DBEF51232"
LOG_FILENAME="meso_sensor_log.txt"
DESTINATION_PATH="$HOME/Downloads/$LOG_FILENAME"

echo "📱 Target Device: Carol’s iPhone 17 pro"
echo "📥 Pulling '$LOG_FILENAME' from $BUNDLE_ID..."

xcrun devicectl device copy from \
  --device "$DEVICE_UUID" \
  --domain-type "appDataContainer" \
  --domain-identifier "$BUNDLE_ID" \
  --source "Documents/$LOG_FILENAME" \
  --destination "$DESTINATION_PATH"

if [ $? -eq 0 ]; then
    echo "✅ Success! Log file saved to: $DESTINATION_PATH"
    
    echo "🧹 Clearing log contents on iPhone..."
    
    # Create temporary empty file on Mac
    EMPTY_TMP=$(mktemp)
    
    # Overwrite remote log with empty file
    xcrun devicectl device copy to \
      --device "$DEVICE_UUID" \
      --domain-type "appDataContainer" \
      --domain-identifier "$BUNDLE_ID" \
      --source "$EMPTY_TMP" \
      --destination "Documents/$LOG_FILENAME" >/dev/null 2>&1

    # Cleanup local temp file
    rm -f "$EMPTY_TMP"

    if [ $? -eq 0 ]; then
        echo "✅ Log file truncated/cleared to 0 bytes on iPhone."
    else
        echo "⚠️ Failed to overwrite log file on iPhone."
    fi
else
    echo "❌ Failed to pull log file."
fi
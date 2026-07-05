import asyncio
from bleak import BleakClient

TARGET_UUID = "BE30EB30-EB1B-6AAD-FB5B-959DBFBA7A76"
CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a9"

async def main():
    print(f"Attempting direct connection to {TARGET_UUID}...")
    
    def decode_and_print(raw_data, source_type):
        try:
            text_data = raw_data.decode('utf-8').strip()
            float_value = float(text_data)
            int_value = int(float_value)
            print(f"[{source_type}] Live PM2.5: {int_value} µg/m³")
        except Exception as e:
            print(f"[{source_type}] Raw Hex: {raw_data.hex().upper()} | String: {raw_data} | Error: {e}")

    # Callback for live notifications
    async def notification_handler(sender, data):
        decode_and_print(data, "NOTIFICATION")

    try:
        async with BleakClient(TARGET_UUID, timeout=15.0) as client:
            print("\n🎉 Connected successfully!")
            
            # Try to turn on notifications
            try:
                print(f"Subscribing to notification stream...")
                await client.start_notify(CHARACTERISTIC_UUID, notification_handler)
                print("Notification subscription armed.")
            except Exception as notify_err:
                print(f"⚠️ Notification subscription failed ({notify_err}), falling back to direct reading...")

            print("\nMonitoring sensor stream. Press Ctrl+C to stop...\n")
            
            # THE FIX: Active Polling Loop
            while True:
                # Forcefully read the data directly from the characteristic slot
                raw_bytes = await client.read_gatt_char(CHARACTERISTIC_UUID)
                decode_and_print(raw_bytes, "DIRECT READ")
                
                await asyncio.sleep(2.0)
                
    except Exception as e:
        print(f"\n❌ Connection failed or dropped: {e}")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nProgram terminated.")
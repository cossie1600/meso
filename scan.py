import asyncio
from bleak import BleakClient
from aiohttp import web

TARGET_UUID = "BE30EB30-EB1B-6AAD-FB5B-959DBFBA7A76"
CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a9"

# Global dictionary to hold the absolute latest live data
live_sensor_data = {
    "status": "Waiting for node...",
    "pm1": "--",
    "pm25": "--",
    "pm10": "--"
}

# 🌐 LOCAL WEB SERVER ENDPOINT: This is what your simulator will talk to
async def handle_get_data(request):
    return web.json_response(live_sensor_data)

def decode_and_update(raw_data, source_type):
    try:
        text_data = raw_data.decode('utf-8').strip()
        components = text_data.split(',')
        
        if len(components) == 3:
            live_sensor_data["pm1"] = components[0]
            live_sensor_data["pm25"] = components[1]
            live_sensor_data["pm10"] = components[2]
            live_sensor_data["status"] = f"Real Data via Python Bridge ({source_type})"
            print(f"📡 Updated Bridge -> PM1.0: {components[0]} | PM2.5: {components[1]} | PM10: {components[2]}")
    except Exception as e:
        print(f"Error parsing data: {e}")

async def notification_handler(sender, data):
    decode_and_update(data, "NOTIFY")

# BLE Core task loop
async def ble_client_task():
    while True:
        try:
            print(f"Attempting Bluetooth connection to {TARGET_UUID}...")
            async with BleakClient(TARGET_UUID, timeout=10.0) as client:
                print("🎉 Python connected to ESP32 Hardware!")
                live_sensor_data["status"] = "Connected to Node via Python"
                await client.start_notify(CHARACTERISTIC_UUID, notification_handler)
                
                while True:
                    raw_bytes = await client.read_gatt_char(CHARACTERISTIC_UUID)
                    decode_and_update(raw_bytes, "POLL")
                    await asyncio.sleep(2.0)
        except Exception as e:
            print(f"❌ BLE connection lost or failed: {e}. Reconnecting in 5s...")
            live_sensor_data["status"] = "Python searching for hardware..."
            await asyncio.sleep(5.0)

async def main():
    # 1. Start the mini local web server on your Mac (Port 8080)
    app = web.Application()
    app.router.add_get('/data', handle_get_data)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, '127.0.0.1', 8080)
    await site.start()
    print("🌐 Local Data Bridge Server running at http://localhost:8080/data")
    
    # 2. Run the BLE task simultaneously alongside the server
    await ble_client_task()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nBridge terminated.")
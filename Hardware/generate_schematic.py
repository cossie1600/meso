import uuid

components = [
    {"ref": "U1", "value": "ESP32-C6-MINI-1", "footprint": "RF_Module:ESP32-C6-MINI-1"},
    {"ref": "J3", "value": "Daughterboard_Interface", "footprint": "Connector_PinHeader_1.27mm:PinHeader_1x04_P1.27mm_Vertical"},
    {"ref": "R1", "value": "4.7k", "footprint": "Resistor_SMD:R_0603_1608Metric"},
    {"ref": "R2", "value": "4.7k", "footprint": "Resistor_SMD:R_0603_1608Metric"},
    {"ref": "C1", "value": "100nF", "footprint": "Capacitor_SMD:C_0603_1608Metric"},
    {"ref": "J1", "value": "USB_C", "footprint": "Connector_USB:USB_C_Receptacle_Palconn_UTC16-G"},
    {"ref": "R3", "value": "5.1k", "footprint": "Resistor_SMD:R_0603_1608Metric"},
    {"ref": "R4", "value": "5.1k", "footprint": "Resistor_SMD:R_0603_1608Metric"},
    {"ref": "J2", "value": "JST_PH_2PIN", "footprint": "Connector_JST:JST_PH_S2B-PH-K_1x02_P2.00mm_Horizontal"},
    {"ref": "U3", "value": "MCP73831", "footprint": "Package_TO_SOT_SMD:SOT-23-5"},
    {"ref": "R5", "value": "10k", "footprint": "Resistor_SMD:R_0603_1608Metric"},
    {"ref": "D1", "value": "BAT54C", "footprint": "Package_TO_SOT_SMD:SOT-23"},
    {"ref": "U4", "value": "AP2112K-3.3", "footprint": "Package_TO_SOT_SMD:SOT-23-5"}
]

nets = {
    "GND": [
        ("U1", "2"), ("U1", "39"),
        ("J3", "1"), ("C1", "2"),
        ("J1", "A1"), ("J1", "A12"), ("J1", "B1"), ("J1", "B12"), ("J1", "SH"),
        ("R3", "2"), ("R4", "2"),
        ("J2", "2"),
        ("U3", "2"), ("R5", "2"),
        ("U4", "2")
    ],
    "+3V3": [
        ("U1", "1"), ("J3", "2"), ("R1", "1"), ("R2", "1"), ("C1", "1"), ("U4", "5")
    ],
    "VBUS_5V": [
        ("J1", "A4"), ("J1", "A9"), ("J1", "B4"), ("J1", "B9"),
        ("U3", "4"),
        ("D1", "1")
    ],
    "VBAT": [
        ("J2", "1"), ("U3", "3"), ("D1", "2")
    ],
    "VSYS": [
        ("D1", "3"), ("U4", "1"), ("U4", "3")
    ],
    "I2C0_SDA": [
        ("U1", "8"), ("J3", "3"), ("R1", "2")
    ],
    "I2C0_SCL": [
        ("U1", "9"), ("J3", "4"), ("R2", "2")
    ],
    "USB_DP": [
        ("U1", "13"), ("J1", "A6"), ("J1", "B6")
    ],
    "USB_DM": [
        ("U1", "12"), ("J1", "A7"), ("J1", "B7")
    ],
    "CC1": [
        ("J1", "A5"), ("R3", "1")
    ],
    "CC2": [
        ("J1", "B5"), ("R4", "1")
    ],
    "PROG": [
        ("U3", "5"), ("R5", "1")
    ]
}

lines = [
    '(export (version "E")',
    '  (design (source "ESP32_C6_Mainboard.sch") (date "2026-09-20") (tool "Python KiCad Netlist Generator"))',
    '  (components'
]

for comp in components:
    lines.append(f'    (comp (ref "{comp["ref"]}") (value "{comp["value"]}") (footprint "{comp["footprint"]}") (tstamp "{uuid.uuid4()}"))')

lines.append('  )\n  (nets')

for code, (net_name, nodes) in enumerate(nets.items(), start=1):
    lines.append(f'    (net (code "{code}") (name "{net_name}")')
    for ref, pin in nodes:
        lines.append(f'      (node (ref "{ref}") (pin "{pin}"))')
    lines.append('    )')

lines.append('  )\n)')

output_path = '/Users/tmai/meso/Hardware/ESP32_C6_BME688.net'
with open(output_path, "w") as f:
    f.write("\n".join(lines))

print(f"SUCCESS: Main Carrier Netlist generated at: {output_path}")

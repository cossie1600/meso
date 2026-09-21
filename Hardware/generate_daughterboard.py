import uuid

# Custom BME688 Daughterboard Components (Address 0x77)
components = [
    {"ref": "U2", "value": "BME688", "footprint": "Package_LGA:Bosch_LGA-8_3x3mm_P0.8mm_ClockwisePinNumbering"},
    {"ref": "C2", "value": "100nF", "footprint": "Capacitor_SMD:C_0603_1608Metric"},
    {"ref": "J4", "value": "Carrier_Header", "footprint": "Connector_PinHeader_1.27mm:PinHeader_1x04_P1.27mm_Vertical"}
]

nets = {
    "GND": [
        ("U2", "1"), ("U2", "7"),
        ("C2", "2"),
        ("J4", "1")
    ],
    "+3V3": [
        ("U2", "6"), ("U2", "8"),  # VDD and VDDIO
        ("U2", "2"), ("U2", "3"),  # CSB and SDO tied to 3.3V -> Sets I2C Address to 0x77
        ("C2", "1"),
        ("J4", "2")
    ],
    "I2C0_SDA": [
        ("U2", "4"),
        ("J4", "3")
    ],
    "I2C0_SCL": [
        ("U2", "5"),
        ("J4", "4")
    ]
}

lines = [
    '(export (version "E")',
    '  (design (source "BME688_Daughterboard.sch") (date "2026-09-19") (tool "Python KiCad Netlist Generator"))',
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

output_path = '/Users/tmai/meso/Hardware/BME688_Daughterboard.net'
with open(output_path, "w") as f:
    f.write("\n".join(lines))

print(f"SUCCESS: BME688 Daughterboard Netlist (Address 0x77) generated at: {output_path}")
import os
import pcbnew

def mm(val):
    return pcbnew.FromMM(val) if hasattr(pcbnew, 'FromMM') else int(val * 1000000)

def make_point(x, y):
    if hasattr(pcbnew, 'VECTOR2I'):
        return pcbnew.VECTOR2I(int(x), int(y))
    return pcbnew.wxPoint(int(x), int(y))

board = pcbnew.GetBoard() if pcbnew.GetBoard() else pcbnew.BOARD()

# Clear Canvas
for item in list(board.GetFootprints()):
    board.Remove(item)
for item in list(board.GetDrawings()):
    board.Remove(item)
for item in list(board.GetTracks()):
    board.Remove(item)

# 1. Board Outline (23mm x 21mm)
center_x, center_y = mm(100), mm(100)
board_w, board_h = mm(23.0), mm(21.0)
half_w, half_h = board_w / 2, board_h / 2

pts = [
    (center_x - half_w, center_y - half_h),
    (center_x + half_w, center_y - half_h),
    (center_x + half_w, center_y + half_h),
    (center_x - half_w, center_y + half_h)
]
for i in range(4):
    seg = pcbnew.PCB_SHAPE(board)
    seg.SetShape(pcbnew.S_SEGMENT)
    seg.SetLayer(pcbnew.Edge_Cuts)
    seg.SetStart(make_point(pts[i][0], pts[i][1]))
    seg.SetEnd(make_point(pts[(i + 1) % 4][0], pts[(i + 1) % 4][1]))
    seg.SetWidth(mm(0.1))
    board.Add(seg)

def build_fp(ref, val, pads_cfg, silk_box=None, is_bottom=False):
    fp = pcbnew.FOOTPRINT(board)
    fp.SetReference(ref)
    fp.SetValue(val)
    layer = pcbnew.B_Cu if is_bottom else pcbnew.F_Cu
    silk_layer = pcbnew.B_SilkS if is_bottom else pcbnew.F_SilkS

    for p_num, px, py, sx, sy, shape, attr, net_name in pads_cfg:
        pad = pcbnew.PAD(fp)
        pad.SetNumber(str(p_num))
        pad.SetShape(shape)
        pad.SetAttribute(attr)
        pad.SetLayer(layer)
        pad.SetPosition(make_point(px, py))
        pad.SetSize(make_point(sx, sy))
        
        if net_name:
            net = board.FindNet(net_name)
            if not net:
                net = pcbnew.NETINFO_ITEM(board, net_name)
                board.Add(net)
            pad.SetNet(net)
        fp.Add(pad)

    if silk_box:
        sx, sy, sw, sh = silk_box
        b_pts = [(sx-sw/2, sy-sh/2), (sx+sw/2, sy-sh/2), (sx+sw/2, sy+sh/2), (sx-sw/2, sy+sh/2)]
        for i in range(4):
            line = pcbnew.PCB_SHAPE(fp)
            line.SetShape(pcbnew.S_SEGMENT)
            line.SetLayer(silk_layer)
            line.SetStart(make_point(b_pts[i][0], b_pts[i][1]))
            line.SetEnd(make_point(b_pts[(i+1)%4][0], b_pts[(i+1)%4][1]))
            line.SetWidth(mm(0.12))
            fp.Add(line)
    return fp

SMD, PTH = pcbnew.PAD_ATTRIB_SMD, pcbnew.PAD_ATTRIB_PTH
RECT, CIRCLE = pcbnew.PAD_SHAPE_RECT, pcbnew.PAD_SHAPE_CIRCLE

# --- FOOTPRINTS ---
# ESP32-C6-MINI-1
esp_cx, esp_cy = center_x + mm(3.0), center_y
esp_pads = []
for i in range(9):
    net = "GND" if i in [0, 8] else ("3V3" if i == 1 else f"ESP_{i+1}")
    esp_pads.append((i+1, esp_cx - mm(6.6), esp_cy - mm(5.0) + mm(1.25*i), mm(1.2), mm(0.7), RECT, SMD, net))
for i in range(9):
    net = "SDA" if (18-i) == 13 else ("SCL" if (18-i) == 14 else f"ESP_{18-i}")
    esp_pads.append((18-i, esp_cx + mm(6.6), esp_cy - mm(5.0) + mm(1.25*i), mm(1.2), mm(0.7), RECT, SMD, net))
board.Add(build_fp("U1", "ESP32-C6-MINI-1", esp_pads, (esp_cx, esp_cy, mm(13.2), mm(16.6))))

# USB-C Port
usb_cx, usb_cy = center_x - half_w + mm(3.5), center_y - mm(5.0)
usb_pads = [
    (1, usb_cx - mm(0.5), usb_cy - mm(1.6), mm(0.4), mm(1.2), RECT, SMD, "GND"),
    (2, usb_cx - mm(0.5), usb_cy - mm(1.0), mm(0.4), mm(1.2), RECT, SMD, "VBUS"),
    (3, usb_cx - mm(0.5), usb_cy - mm(0.35), mm(0.4), mm(1.2), RECT, SMD, "CC1"),
    (4, usb_cx - mm(0.5), usb_cy + mm(0.35), mm(0.4), mm(1.2), RECT, SMD, "CC2"),
    (5, usb_cx - mm(0.5), usb_cy + mm(1.0), mm(0.4), mm(1.2), RECT, SMD, "VBUS"),
    (6, usb_cx - mm(0.5), usb_cy + mm(1.6), mm(0.4), mm(1.2), RECT, SMD, "GND")
]
board.Add(build_fp("J1", "USB_C", usb_pads, (usb_cx, usb_cy, mm(7.0), mm(5.0))))

# MCP73831 Charger
mcp_cx, mcp_cy = center_x - mm(6.5), center_y - mm(1.0)
mcp_pads = [
    (1, mcp_cx - mm(0.95), mcp_cy + mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "NC"),
    (2, mcp_cx, mcp_cy + mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "GND"),
    (3, mcp_cx + mm(0.95), mcp_cy + mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "VBAT"),
    (4, mcp_cx + mm(0.95), mcp_cy - mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "VBUS"),
    (5, mcp_cx - mm(0.95), mcp_cy - mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "PROG")
]
board.Add(build_fp("U2", "MCP73831", mcp_pads, (mcp_cx, mcp_cy, mm(3.0), mm(3.0))))

# Power-Path P-FET (Q1: SOT-23)
pfet_cx, pfet_cy = center_x - mm(2.5), center_y - mm(1.0)
pfet_pads = [
    (1, pfet_cx - mm(0.95), pfet_cy + mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "VBUS"), # Gate tied to VBUS
    (2, pfet_cx + mm(0.95), pfet_cy + mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "SYS_IN"),# Drain to LDO
    (3, pfet_cx, pfet_cy - mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "VBAT")             # Source from Battery
]
board.Add(build_fp("Q1", "P-FET_PowerPath", pfet_pads, (pfet_cx, pfet_cy, mm(2.8), mm(2.8))))

# Power-Path Schottky Diode (D1: SOD-123)
d1_cx, d1_cy = center_x - mm(2.5), center_y + mm(2.5)
d1_pads = [
    (1, d1_cx - mm(1.0), d1_cy, mm(0.8), mm(1.0), RECT, SMD, "VBUS"),  # Anode
    (2, d1_cx + mm(1.0), d1_cy, mm(0.8), mm(1.0), RECT, SMD, "SYS_IN") # Cathode
]
board.Add(build_fp("D1", "Schottky_Diode", d1_pads, (d1_cx, d1_cy, mm(2.8), mm(1.6))))

# 3.3V LDO Regulator (AP2112K-3.3)
ldo_cx, ldo_cy = center_x - mm(2.0), center_y + mm(6.0)
ldo_pads = [
    (1, ldo_cx - mm(0.95), ldo_cy - mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "SYS_IN"),
    (2, ldo_cx, ldo_cy - mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "GND"),
    (3, ldo_cx + mm(0.95), ldo_cy - mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "SYS_IN"),
    (4, ldo_cx + mm(0.95), ldo_cy + mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "NC"),
    (5, ldo_cx - mm(0.95), ldo_cy + mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "3V3")
]
board.Add(build_fp("U3", "AP2112K-3.3", ldo_pads, (ldo_cx, ldo_cy, mm(3.0), mm(3.0))))

# JST Battery Connector
jst_cx, jst_cy = center_x - mm(6.5), center_y + mm(7.0)
jst_pads = [
    (1, jst_cx - mm(1.0), jst_cy, mm(1.4), mm(1.4), CIRCLE, PTH, "VBAT"),
    (2, jst_cx + mm(1.0), jst_cy, mm(1.4), mm(1.4), CIRCLE, PTH, "GND")
]
board.Add(build_fp("J2", "JST_PH", jst_pads, (jst_cx, jst_cy, mm(6.0), mm(4.5))))

# Qwiic Connector (Bottom Side)
qwiic_cx, qwiic_cy = center_x + mm(3.0), center_y + half_h - mm(2.0)
qwiic_pads = [
    (1, qwiic_cx - mm(1.5), qwiic_cy, mm(0.5), mm(1.0), RECT, SMD, "GND"),
    (2, qwiic_cx - mm(0.5), qwiic_cy, mm(0.5), mm(1.0), RECT, SMD, "3V3"),
    (3, qwiic_cx + mm(0.5), qwiic_cy, mm(0.5), mm(1.0), RECT, SMD, "SDA"),
    (4, qwiic_cx + mm(1.5), qwiic_cy, mm(0.5), mm(1.0), RECT, SMD, "SCL")
]
board.Add(build_fp("J3", "Qwiic", qwiic_pads, (qwiic_cx, qwiic_cy, mm(5.5), mm(3.5)), is_bottom=True))

# --- POWER PATH ROUTING ---
def add_track(start_p, end_p, net_name, width_mm=0.25, layer_id=pcbnew.F_Cu):
    track = pcbnew.PCB_TRACK(board)
    track.SetStart(make_point(start_p[0], start_p[1]))
    track.SetEnd(make_point(end_p[0], end_p[1]))
    track.SetWidth(mm(width_mm))
    track.SetLayer(layer_id)
    net = board.FindNet(net_name)
    if net:
        track.SetNet(net)
    board.Add(track)

# 1. Route VBUS -> MCP73831 Pin 4, Q1 Gate (Pin 1), D1 Anode (Pin 1)
add_track((usb_cx - mm(0.5), usb_cy - mm(1.0)), (mcp_cx + mm(0.95), mcp_cy - mm(1.1)), "VBUS", 0.4)
add_track((mcp_cx + mm(0.95), mcp_cy - mm(1.1)), (pfet_cx - mm(0.95), pfet_cy + mm(1.1)), "VBUS", 0.3)
add_track((pfet_cx - mm(0.95), pfet_cy + mm(1.1)), (d1_cx - mm(1.0), d1_cy), "VBUS", 0.3)

# 2. Route VBAT -> Charger Pin 3, JST Pin 1, Q1 Source (Pin 3)
add_track((mcp_cx + mm(0.95), mcp_cy + mm(1.1)), (jst_cx - mm(1.0), jst_cy), "VBAT", 0.4)
add_track((jst_cx - mm(1.0), jst_cy), (pfet_cx, pfet_cy - mm(1.1)), "VBAT", 0.4)

# 3. Route SYS_IN -> Q1 Drain (Pin 2), D1 Cathode (Pin 2) -> LDO Input (Pins 1 & 3)
add_track((pfet_cx + mm(0.95), pfet_cy + mm(1.1)), (d1_cx + mm(1.0), d1_cy), "SYS_IN", 0.4)
add_track((d1_cx + mm(1.0), d1_cy), (ldo_cx - mm(0.95), ldo_cy - mm(1.1)), "SYS_IN", 0.4)

# 4. Route 3V3 -> LDO Output (Pin 5) to ESP32 & Qwiic
add_track((ldo_cx - mm(0.95), ldo_cy + mm(1.1)), (esp_cx - mm(6.6), esp_cy - mm(3.75)), "3V3", 0.35)
add_track((esp_cx - mm(6.6), esp_cy - mm(3.75)), (qwiic_cx - mm(0.5), qwiic_cy), "3V3", 0.35, pcbnew.B_Cu)

# 5. Route SDA / SCL
add_track((esp_cx + mm(6.6), esp_cy + mm(0.0)), (qwiic_cx + mm(0.5), qwiic_cy), "SDA", 0.2, pcbnew.B_Cu)
add_track((esp_cx + mm(6.6), esp_cy + mm(1.25)), (qwiic_cx + mm(1.5), qwiic_cy), "SCL", 0.2, pcbnew.B_Cu)

# 6. Route GND Ground Rail
add_track((usb_cx - mm(0.5), usb_cy - mm(1.6)), (mcp_cx, mcp_cy + mm(1.1)), "GND", 0.4)
add_track((mcp_cx, mcp_cy + mm(1.1)), (ldo_cx, ldo_cy - mm(1.1)), "GND", 0.4)
add_track((ldo_cx, ldo_cy - mm(1.1)), (jst_cx + mm(1.0), jst_cy), "GND", 0.4)
add_track((jst_cx + mm(1.0), jst_cy), (qwiic_cx - mm(1.5), qwiic_cy), "GND", 0.4, pcbnew.B_Cu)

pcbnew.Refresh()

# Save Board
output_dir = os.path.join(os.path.expanduser("~"), "KiCad_Gerbers_Output")
os.makedirs(output_dir, exist_ok=True)
save_path = os.path.join(output_dir, "ESP32_C6_PowerPath_Ready.kicad_pcb")
pcbnew.SaveBoard(save_path, board)

print(f"Board regenerated with true Hardware Power-Path routing: {save_path}")
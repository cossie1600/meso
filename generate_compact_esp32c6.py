import os
import pcbnew

def mm(val):
    return pcbnew.FromMM(val) if hasattr(pcbnew, 'FromMM') else int(val * 1000000)

def make_point(x, y):
    if hasattr(pcbnew, 'VECTOR2I'):
        return pcbnew.VECTOR2I(int(x), int(y))
    return pcbnew.wxPoint(int(x), int(y))

# 1. Initialize Board & Wipe Canvas
board = pcbnew.GetBoard() if pcbnew.GetBoard() else pcbnew.BOARD()

for item in list(board.GetFootprints()):
    board.Remove(item)
for item in list(board.GetDrawings()):
    board.Remove(item)

# 2. Board Dimensions: Compact 23mm x 21mm
center_x, center_y = mm(100), mm(100)
board_w, board_h = mm(23.0), mm(21.0)
half_w, half_h = board_w / 2, board_h / 2

# Draw Edge Cuts Outline
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

# Footprint Builder Helper
def build_custom_footprint(ref, value, pads_config, silk_box=None, is_bottom=False):
    fp = pcbnew.FOOTPRINT(board)
    fp.SetReference(ref)
    fp.SetValue(value)
    layer = pcbnew.B_Cu if is_bottom else pcbnew.F_Cu
    silk_layer = pcbnew.B_SilkS if is_bottom else pcbnew.F_SilkS

    # Add Pads
    for pad_num, pos_x, pos_y, size_x, size_y, shape, attr, net_name in pads_config:
        pad = pcbnew.PAD(fp)
        pad.SetNumber(str(pad_num))
        pad.SetShape(shape)
        pad.SetAttribute(attr)
        pad.SetLayer(layer)
        pad.SetPosition(make_point(pos_x, pos_y))
        pad.SetSize(make_point(size_x, size_y))
        
        if net_name:
            net = board.FindNet(net_name)
            if not net:
                net = pcbnew.NETINFO_ITEM(board, net_name)
                board.Add(net)
            pad.SetNet(net)
            
        fp.Add(pad)

    # Add Silkscreen Outline for 3D Visualizer
    if silk_box:
        sx, sy, sw, sh = silk_box
        box_pts = [
            (sx - sw/2, sy - sh/2), (sx + sw/2, sy - sh/2),
            (sx + sw/2, sy + sh/2), (sx - sw/2, sy + sh/2)
        ]
        for i in range(4):
            line = pcbnew.PCB_SHAPE(fp)
            line.SetShape(pcbnew.S_SEGMENT)
            line.SetLayer(silk_layer)
            line.SetStart(make_point(box_pts[i][0], box_pts[i][1]))
            line.SetEnd(make_point(box_pts[(i + 1) % 4][0], box_pts[(i + 1) % 4][1]))
            line.SetWidth(mm(0.12))
            fp.Add(line)

    return fp

SMD = pcbnew.PAD_ATTRIB_SMD
PTH = pcbnew.PAD_ATTRIB_PTH
RECT = pcbnew.PAD_SHAPE_RECT
CIRCLE = pcbnew.PAD_SHAPE_CIRCLE

# -------------------------------------------------------------
# 1. ESP32-C6-MINI-1 Module (Center-Right, Top Side)
# -------------------------------------------------------------
esp_cx, esp_cy = center_x + mm(3.0), center_y
esp_pads = []
for i in range(9):
    esp_pads.append((i + 1, esp_cx - mm(6.6), esp_cy - mm(5.0) + mm(1.25 * i), mm(1.2), mm(0.7), RECT, SMD, f"ESP_{i+1}"))
for i in range(9):
    esp_pads.append((18 - i, esp_cx + mm(6.6), esp_cy - mm(5.0) + mm(1.25 * i), mm(1.2), mm(0.7), RECT, SMD, f"ESP_{18-i}"))

board.Add(build_custom_footprint("U1", "ESP32-C6-MINI-1", esp_pads, silk_box=(esp_cx, esp_cy, mm(13.2), mm(16.6))))

# -------------------------------------------------------------
# 2. USB Type-C Connector (Top-Left Edge, Top Side)
# -------------------------------------------------------------
usb_cx, usb_cy = center_x - half_w + mm(3.5), center_y - mm(5.0)
usb_pads = [
    (1, usb_cx - mm(0.5), usb_cy - mm(1.6), mm(0.4), mm(1.2), RECT, SMD, "GND"),
    (2, usb_cx - mm(0.5), usb_cy - mm(1.0), mm(0.4), mm(1.2), RECT, SMD, "VBUS"),
    (3, usb_cx - mm(0.5), usb_cy - mm(0.35), mm(0.4), mm(1.2), RECT, SMD, "USB_DN"),
    (4, usb_cx - mm(0.5), usb_cy + mm(0.35), mm(0.4), mm(1.2), RECT, SMD, "USB_DP"),
    (5, usb_cx - mm(0.5), usb_cy + mm(1.0), mm(0.4), mm(1.2), RECT, SMD, "VBUS"),
    (6, usb_cx - mm(0.5), usb_cy + mm(1.6), mm(0.4), mm(1.2), RECT, SMD, "GND")
]
board.Add(build_custom_footprint("J1", "USB_C", usb_pads, silk_box=(usb_cx, usb_cy, mm(7.0), mm(5.0))))

# -------------------------------------------------------------
# 3. MCP73831 Charger IC (Middle-Left, Top Side)
# -------------------------------------------------------------
mcp_cx, mcp_cy = center_x - mm(6.5), center_y + mm(1.5)
mcp_pads = [
    (1, mcp_cx - mm(0.95), mcp_cy + mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "STAT"),
    (2, mcp_cx, mcp_cy + mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "GND"),
    (3, mcp_cx + mm(0.95), mcp_cy + mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "VBAT"),
    (4, mcp_cx + mm(0.95), mcp_cy - mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "VBUS"),
    (5, mcp_cx - mm(0.95), mcp_cy - mm(1.1), mm(0.5), mm(0.8), RECT, SMD, "PROG")
]
board.Add(build_custom_footprint("U2", "MCP73831", mcp_pads, silk_box=(mcp_cx, mcp_cy, mm(3.0), mm(3.0))))

# -------------------------------------------------------------
# 4. JST-PH 2-Pin Battery Connector (Bottom-Left, Top Side)
# -------------------------------------------------------------
jst_cx, jst_cy = center_x - mm(6.5), center_y + mm(7.0)
jst_pads = [
    (1, jst_cx - mm(1.0), jst_cy, mm(1.4), mm(1.4), CIRCLE, PTH, "VBAT"),
    (2, jst_cx + mm(1.0), jst_cy, mm(1.4), mm(1.4), CIRCLE, PTH, "GND")
]
board.Add(build_custom_footprint("J2", "JST_PH_LiPo", jst_pads, silk_box=(jst_cx, jst_cy, mm(6.0), mm(4.5))))

# -------------------------------------------------------------
# 5. Qwiic / STEMMA QT Connector (Bottom Edge, Bottom Side)
# -------------------------------------------------------------
qwiic_cx, qwiic_cy = center_x + mm(3.0), center_y + half_h - mm(2.0)
qwiic_pads = [
    (1, qwiic_cx - mm(1.5), qwiic_cy, mm(0.5), mm(1.0), RECT, SMD, "GND"),
    (2, qwiic_cx - mm(0.5), qwiic_cy, mm(0.5), mm(1.0), RECT, SMD, "3V3"),
    (3, qwiic_cx + mm(0.5), qwiic_cy, mm(0.5), mm(1.0), RECT, SMD, "SDA"),
    (4, qwiic_cx + mm(1.5), qwiic_cy, mm(0.5), mm(1.0), RECT, SMD, "SCL")
]
board.Add(build_custom_footprint("J3", "Qwiic_Connector", qwiic_pads, silk_box=(qwiic_cx, qwiic_cy, mm(5.5), mm(3.5)), is_bottom=True))

pcbnew.Refresh()

# Save Board
output_dir = os.path.join(os.path.expanduser("~"), "KiCad_Gerbers_Output")
os.makedirs(output_dir, exist_ok=True)
save_path = os.path.join(output_dir, "ESP32_C6_Compact_3D.kicad_pcb")
pcbnew.SaveBoard(save_path, board)

print(f"Board refreshed! All 5 components locked in place: {save_path}")
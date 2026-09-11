import os
import sys
import pcbnew

def mm(val):
    return pcbnew.FromMM(val) if hasattr(pcbnew, 'FromMM') else int(val * 1000000)

def make_point(x, y):
    if hasattr(pcbnew, 'VECTOR2I'):
        return pcbnew.VECTOR2I(int(x), int(y))
    return pcbnew.wxPoint(int(x), int(y))

# 1. Bind to Active Board & Clear Canvas
board = pcbnew.GetBoard() if pcbnew.GetBoard() else pcbnew.BOARD()

for item in list(board.GetFootprints()):
    board.Remove(item)
for item in list(board.GetDrawings()):
    board.Remove(item)

# 2. Board Dimensions (23.0 mm x 21.0 mm)
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

# 3. Detect System KiCad Footprint Library Directory
mac_path = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"
win_path = "C:/Program Files/KiCad/8.0/share/kicad/footprints"
linux_path = "/usr/share/kicad/footprints"

kicad_fp_dir = ""
for p in [mac_path, win_path, linux_path]:
    if os.path.exists(p):
        kicad_fp_dir = p
        break

def load_official_footprint(lib_folder, fp_name, ref, val, pos_x, pos_y, rotation_deg=0):
    full_lib_path = os.path.join(kicad_fp_dir, f"{lib_folder}.pretty")
    
    if os.path.exists(full_lib_path):
        fp = pcbnew.FootprintLoad(full_lib_path, fp_name)
    else:
        fp = None

    # Fallback to direct library search if path resolution differs
    if not fp:
        try:
            fp = pcbnew.FootprintLoad("", f"{lib_folder}:{fp_name}")
        except Exception:
            fp = None

    if not fp:
        print(f"Warning: Could not load {lib_folder}:{fp_name}")
        return None

    fp.SetReference(ref)
    fp.SetValue(val)
    fp.SetPosition(make_point(pos_x, pos_y))
    if rotation_deg != 0:
        fp.SetOrientation(pcbnew.EDA_ANGLE(rotation_deg, pcbnew.DEGREES_T))
    board.Add(fp)
    return fp

# -------------------------------------------------------------
# Footprint Loading
# -------------------------------------------------------------
# 1. USB-C Connector (Left Edge)
load_official_footprint(
    "Connector_USB", "USB_C_Receptacle_GNS_TYPE-C-16P", 
    "J1", "USB_C", 
    center_x - half_w + mm(4.0), center_y - mm(4.0), 
    rotation_deg=90
)

# 2. JST-PH 2-Pin Battery Connector (Top-Left Edge)
load_official_footprint(
    "Connector_JST", "JST_PH_S2B-PH-SM4-TB_1x02-1MP_P2.00mm_Horizontal", 
    "J2", "LiPo_Bat", 
    center_x - mm(6.0), center_y - mm(6.5), 
    rotation_deg=0
)

# 3. Qwiic Connector (Bottom Edge)
load_official_footprint(
    "Connector_JST", "JST_SH_BM04B-SRSS-TB_1x04-1MP_P1.00mm_Horizontal", 
    "J3", "Qwiic", 
    center_x, center_y + half_h - mm(2.5), 
    rotation_deg=180
)

# 4. MCP73831 Charger IC (SOT-23-5)
load_official_footprint(
    "Package_TO_SOT_SMD", "SOT-23-5", 
    "U2", "MCP73831", 
    center_x - mm(6.0), center_y + mm(2.0), 
    rotation_deg=0
)

# 5. ESP32-C6-MINI-1 Module (Right Side)
load_official_footprint(
    "RF_Module", "ESP32-C6-MINI-1", 
    "U1", "ESP32-C6-MINI-1", 
    center_x + mm(3.0), center_y, 
    rotation_deg=0
)

pcbnew.Refresh()

# Save Board
output_dir = os.path.join(os.path.expanduser("~"), "KiCad_Gerbers_Output")
os.makedirs(output_dir, exist_ok=True)
save_path = os.path.join(output_dir, "ESP32_C6_Compact_3D.kicad_pcb")
pcbnew.SaveBoard(save_path, board)

print(f"Successfully generated 3D board at: {save_path}")
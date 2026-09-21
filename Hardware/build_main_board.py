import pcbnew
import _pcbnew

board = pcbnew.GetBoard()

def c_call(func_name, *args):
    func = getattr(_pcbnew, func_name, None)
    if func:
        try: return func(*args)
        except Exception: pass
    return None

def get_items(method):
    if hasattr(board, method):
        try: return list(getattr(board, method)())
        except Exception: pass
    res = c_call(f"BOARD_{method}", board)
    return list(res) if res else []

def remove_item(item):
    if hasattr(board, "Remove"):
        try: board.Remove(item); return
        except Exception: pass
    c_call("BOARD_Remove", board, item)

def add_item(item):
    if hasattr(board, "Add"):
        try: board.Add(item); return
        except Exception: pass
    c_call("BOARD_Add", board, item)

def find_fp(ref):
    if hasattr(board, "FindFootprintByReference"):
        try:
            res = board.FindFootprintByReference(ref)
            if res: return res
        except Exception: pass
    return c_call("BOARD_FindFootprintByReference", board, ref)

# 1. Clear existing board items
for tr in get_items("GetTracks"): remove_item(tr)
for zn in get_items("GetZones"): remove_item(zn)
for dr in get_items("GetDrawings"): remove_item(dr)

# 2. Configure Board Design Rules (PCBWay PCBA Standard)
try:
    ds = board.GetDesignSettings() if hasattr(board, "GetDesignSettings") else c_call("BOARD_GetDesignSettings", board)
    if ds:
        if hasattr(ds, "m_CopperEdgeClearance"): ds.m_CopperEdgeClearance = int(pcbnew.FromMM(0.30))
        if hasattr(ds, "m_CopperToHoleClearance"): ds.m_CopperToHoleClearance = int(pcbnew.FromMM(0.18))
        if hasattr(ds, "m_HoleToHoleMin"): ds.m_HoleToHoleMin = int(pcbnew.FromMM(0.18))
except Exception:
    pass

# 3. Purge stock internal keepouts and extra courtyards from U1
fp_u1 = find_fp("U1")
if fp_u1:
    try:
        zones = list(fp_u1.Zones()) if hasattr(fp_u1, "Zones") else list(c_call("FOOTPRINT_Zones", fp_u1) or [])
        for z in zones:
            if hasattr(fp_u1, "Remove"): fp_u1.Remove(z)
            else: c_call("FOOTPRINT_Remove", fp_u1, z)
    except Exception: pass

    try:
        items = list(fp_u1.GraphicalItems()) if hasattr(fp_u1, "GraphicalItems") else list(c_call("FOOTPRINT_GraphicalItems", fp_u1) or [])
        for item in items:
            layer = item.GetLayer() if hasattr(item, "GetLayer") else c_call("BOARD_ITEM_GetLayer", item)
            if layer in [pcbnew.F_CrtYd, pcbnew.Cmts_User, pcbnew.Dwgs_User]:
                if hasattr(fp_u1, "Remove"): fp_u1.Remove(item)
                else: c_call("FOOTPRINT_Remove", fp_u1, item)
    except Exception: pass

# 4. Draw Board Outline (31.7 mm x 20.0 mm)
OFFSET_X, OFFSET_Y = 100.0, 100.0
board_w, board_h = 31.7, 20.0
rect = [(0.0, 0.0), (board_w, 0.0), (board_w, board_h), (0.0, board_h)]

def mm_vec(x, y):
    return pcbnew.VECTOR2I(int(pcbnew.FromMM(OFFSET_X + x)), int(pcbnew.FromMM(OFFSET_Y + y)))

for i in range(len(rect)):
    p1, p2 = rect[i], rect[(i + 1) % len(rect)]
    shape = pcbnew.PCB_SHAPE(board)
    shape.SetShape(pcbnew.SHAPE_T_SEGMENT)
    shape.SetLayer(pcbnew.Edge_Cuts)
    shape.SetStart(mm_vec(p1[0], p1[1]))
    shape.SetEnd(mm_vec(p2[0], p2[1]))
    shape.SetWidth(int(pcbnew.FromMM(0.1)))
    add_item(shape)

# 5. Position Components (J2 at Y=6.2mm fully inside board; J1 at X=28.9mm protruding ~0.8mm)
def set_fp(ref, x, y, rot):
    fp = find_fp(ref)
    if fp:
        pos = mm_vec(x, y)
        if hasattr(fp, "SetPosition"): fp.SetPosition(pos)
        else: c_call("FOOTPRINT_SetPosition", fp, pos)
        if hasattr(fp, "SetOrientationDegrees"): fp.SetOrientationDegrees(rot)
        else: c_call("FOOTPRINT_SetOrientationDegrees", fp, rot)

set_fp("J3", 1.2, 7.5, 0.0)      # Daughterboard Header
set_fp("R1", 1.2, 2.0, 90.0)     # SDA Pullup
set_fp("R2", 1.2, 16.5, 90.0)    # SCL Pullup
set_fp("U4", 4.3, 2.5, 0.0)      # AP2112K LDO
set_fp("D1", 4.3, 16.5, 0.0)     # BAT54C Diode
set_fp("C1", 4.4, 9.5, 0.0)      # Decoupling Cap
set_fp("U1", 13.3, 10.5, 0.0)    # ESP32-C6 MCU
set_fp("J2", 22.5, 6.2, 180.0)   # JST-PH Battery Connector (Fully Inside)
set_fp("J1", 28.9, 14.0, 90.0)   # USB-C Connector (Protruding ~0.8mm / 10%)
set_fp("R3", 29.8, 2.0, 90.0)    # CC1 Resistor
set_fp("R4", 29.8, 5.5, 90.0)    # CC2 Resistor
set_fp("U3", 13.3, 18.25, 0.0)   # MCP73831 Charger
set_fp("R5", 18.0, 18.25, 0.0)   # PROG Resistor

if hasattr(pcbnew, "Refresh"): pcbnew.Refresh()
print("SUCCESS: Main Board placement updated!")

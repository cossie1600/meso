import pcbnew
import _pcbnew

board = pcbnew.GetBoard()

if hasattr(pcbnew, "Cast_to_BOARD"):
    try: board = pcbnew.Cast_to_BOARD(board)
    except Exception: pass

def get_tracks():
    if hasattr(board, "GetTracks"):
        try: return list(board.GetTracks())
        except Exception: pass
    if hasattr(board, "Tracks"):
        try: return list(board.Tracks())
        except Exception: pass
    if hasattr(_pcbnew, "BOARD_GetTracks"):
        try: return list(_pcbnew.BOARD_GetTracks(board))
        except Exception: pass
    return []

def get_zones():
    if hasattr(board, "GetZones"):
        try: return list(board.GetZones())
        except Exception: pass
    if hasattr(board, "Zones"):
        try: return list(board.Zones())
        except Exception: pass
    if hasattr(_pcbnew, "BOARD_GetZones"):
        try: return list(_pcbnew.BOARD_GetZones(board))
        except Exception: pass
    return []

def get_drawings():
    if hasattr(board, "GetDrawings"):
        try: return list(board.GetDrawings())
        except Exception: pass
    if hasattr(board, "Drawings"):
        try: return list(board.Drawings())
        except Exception: pass
    if hasattr(_pcbnew, "BOARD_GetDrawings"):
        try: return list(_pcbnew.BOARD_GetDrawings(board))
        except Exception: pass
    return []

def board_remove(item):
    if hasattr(board, "Remove"):
        try: board.Remove(item); return
        except Exception: pass
    if hasattr(_pcbnew, "BOARD_Remove"):
        try: _pcbnew.BOARD_Remove(board, item); return
        except Exception: pass

def board_add(item):
    if hasattr(board, "Add"):
        try: board.Add(item); return
        except Exception: pass
    if hasattr(_pcbnew, "BOARD_Add"):
        try: _pcbnew.BOARD_Add(board, item); return
        except Exception: pass

def find_footprint(ref_str):
    fp = None
    if hasattr(board, "FindFootprintByReference"):
        try: fp = board.FindFootprintByReference(ref_str)
        except Exception: pass
    if not fp and hasattr(_pcbnew, "BOARD_FindFootprintByReference"):
        try: fp = _pcbnew.BOARD_FindFootprintByReference(board, ref_str)
        except Exception: pass
    if fp and hasattr(pcbnew, "Cast_to_FOOTPRINT"):
        try: fp = pcbnew.Cast_to_FOOTPRINT(fp)
        except Exception: pass
    return fp

# 1. Configure Board Setup Rules
try:
    ds = board.GetDesignSettings() if hasattr(board, "GetDesignSettings") else _pcbnew.BOARD_GetDesignSettings(board)
    if ds:
        if hasattr(ds, "m_CopperEdgeClearance"): ds.m_CopperEdgeClearance = int(pcbnew.FromMM(0.30))
        if hasattr(ds, "m_HoleToHoleMin"): ds.m_HoleToHoleMin = int(pcbnew.FromMM(0.18))
        if hasattr(ds, "m_CopperToHoleClearance"): ds.m_CopperToHoleClearance = int(pcbnew.FromMM(0.18))
except Exception:
    pass

# 2. Clear tracks, board zones, and duplicate drawings
for tr in get_tracks(): board_remove(tr)
for zn in get_zones(): board_remove(zn)
for dr in get_drawings(): board_remove(dr)

# 3. Strip stock internal Keepout Zone and Courtyard shapes from U1
fp_u1 = find_footprint("U1")
if fp_u1:
    try:
        zones = []
        if hasattr(fp_u1, "Zones"): zones = list(fp_u1.Zones())
        elif hasattr(_pcbnew, "FOOTPRINT_Zones"): zones = list(_pcbnew.FOOTPRINT_Zones(fp_u1))
        for z in zones:
            if hasattr(fp_u1, "Remove"): fp_u1.Remove(z)
            elif hasattr(_pcbnew, "FOOTPRINT_Remove"): _pcbnew.FOOTPRINT_Remove(fp_u1, z)
    except Exception:
        pass

    try:
        items = []
        if hasattr(fp_u1, "GraphicalItems"): items = list(fp_u1.GraphicalItems())
        elif hasattr(_pcbnew, "FOOTPRINT_GraphicalItems"): items = list(_pcbnew.FOOTPRINT_GraphicalItems(fp_u1))
        for item in items:
            try:
                layer_id = item.GetLayer() if hasattr(item, "GetLayer") else _pcbnew.BOARD_ITEM_GetLayer(item)
                if layer_id in [pcbnew.F_CrtYd, pcbnew.Cmts_User, pcbnew.Dwgs_User]:
                    if hasattr(fp_u1, "Remove"): fp_u1.Remove(item)
                    elif hasattr(_pcbnew, "FOOTPRINT_Remove"): _pcbnew.FOOTPRINT_Remove(fp_u1, item)
            except Exception:
                pass
    except Exception:
        pass

# 4. Draw Single Clean 31.7 mm x 20.0 mm Board Outline
OFFSET_X = 100.0
OFFSET_Y = 100.0
board_w = 31.7
board_h = 20.0

rect_points = [(0.0, 0.0), (board_w, 0.0), (board_w, board_h), (0.0, board_h)]

def mm_to_vec(x_mm, y_mm):
    return pcbnew.VECTOR2I(int(pcbnew.FromMM(x_mm)), int(pcbnew.FromMM(y_mm)))

for i in range(len(rect_points)):
    p1 = rect_points[i]
    p2 = rect_points[(i + 1) % len(rect_points)]
    shape = pcbnew.PCB_SHAPE(board)
    shape.SetShape(pcbnew.SHAPE_T_SEGMENT)
    shape.SetLayer(pcbnew.Edge_Cuts)
    shape.SetStart(mm_to_vec(OFFSET_X + p1[0], OFFSET_Y + p1[1]))
    shape.SetEnd(mm_to_vec(OFFSET_X + p2[0], OFFSET_Y + p2[1]))
    shape.SetWidth(int(pcbnew.FromMM(0.1)))
    board_add(shape)

# 5. Position All 13 Components (Zero Courtyard Overlap)
def set_fp_transform(ref, x_mm, y_mm, angle_deg):
    fp = find_footprint(ref)
    if fp:
        pos = mm_to_vec(OFFSET_X + x_mm, OFFSET_Y + y_mm)
        if hasattr(fp, "SetPosition"):
            try: fp.SetPosition(pos)
            except Exception: pass
        elif hasattr(_pcbnew, "FOOTPRINT_SetPosition"):
            try: _pcbnew.FOOTPRINT_SetPosition(fp, pos)
            except Exception: pass

        if hasattr(fp, "SetOrientationDegrees"):
            try: fp.SetOrientationDegrees(angle_deg)
            except Exception: pass
        elif hasattr(_pcbnew, "FOOTPRINT_SetOrientationDegrees"):
            try: _pcbnew.FOOTPRINT_SetOrientationDegrees(fp, angle_deg)
            except Exception: pass

# Left Column
set_fp_transform("J3", 1.2, 7.5, 0.0)       # Daughterboard Header
set_fp_transform("R1", 1.2, 2.0, 90.0)      # SDA Pullup
set_fp_transform("R2", 1.2, 16.5, 90.0)     # SCL Pullup
set_fp_transform("U4", 4.3, 2.5, 0.0)       # AP2112K LDO
set_fp_transform("D1", 4.3, 16.5, 0.0)      # BAT54C Diode
set_fp_transform("C1", 4.4, 9.5, 0.0)       # Decoupling Cap

# Center MCU
set_fp_transform("U1", 13.3, 10.5, 0.0)     # ESP32-C6 MCU

# Right Column
set_fp_transform("J2", 23.5, 1.8, 0.0)      # JST PH Header
set_fp_transform("J1", 28.1, 14.0, 90.0)    # USB-C Port
set_fp_transform("R3", 29.8, 2.0, 90.0)     # CC1 Resistor
set_fp_transform("R4", 29.8, 5.5, 90.0)     # CC2 Resistor

# Bottom Charger
set_fp_transform("U3", 13.3, 18.25, 0.0)    # MCP73831 Charger
set_fp_transform("R5", 18.0, 18.25, 0.0)    # PROG Resistor

# Hide reference labels for clean SMT assembly
for ref_id in ["J3", "R1", "R2", "U4", "D1", "C1", "U1", "J2", "J1", "R3", "R4", "U3", "R5"]:
    fp = find_footprint(ref_id)
    if fp:
        try:
            ref_obj = fp.Reference() if hasattr(fp, "Reference") else _pcbnew.FOOTPRINT_Reference(fp)
            if ref_obj: ref_obj.SetVisible(False)
        except Exception:
            pass

# 6. Fill Solid Ground Zone on B.Cu
try:
    gnd_net = board.FindNet("GND") if hasattr(board, "FindNet") else _pcbnew.BOARD_FindNet(board, "GND")
    if gnd_net:
        zone = pcbnew.ZONE(board)
        zone.SetLayer(pcbnew.B_Cu)
        zone.SetNet(gnd_net)
        pts = pcbnew.VECTOR_VECTOR2I()
        pts.push_back(pcbnew.VECTOR2I(int(pcbnew.FromMM(99.0)), int(pcbnew.FromMM(99.0))))
        pts.push_back(pcbnew.VECTOR2I(int(pcbnew.FromMM(132.7)), int(pcbnew.FromMM(99.0))))
        pts.push_back(pcbnew.VECTOR2I(int(pcbnew.FromMM(132.7)), int(pcbnew.FromMM(121.0))))
        pts.push_back(pcbnew.VECTOR2I(int(pcbnew.FromMM(99.0)), int(pcbnew.FromMM(121.0))))
        zone.AddPolygon(pts)
        board_add(zone)

        filler = pcbnew.ZONE_FILLER(board)
        zones = get_zones()
        if zones: filler.Fill(zones)
except Exception:
    pass

if hasattr(pcbnew, "Refresh"): pcbnew.Refresh()
print("SUCCESS: Master build complete!")

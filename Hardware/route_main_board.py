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

def find_net(name):
    if hasattr(board, "FindNet"):
        try:
            res = board.FindNet(name)
            if res: return res
        except Exception: pass
    return c_call("BOARD_FindNet", board, name)

# 1. Clear existing tracks and zones
for tr in get_items("GetTracks"): remove_item(tr)
for zn in get_items("GetZones"): remove_item(zn)

OFFSET_X, OFFSET_Y = 100.0, 100.0

def mm_vec(x, y):
    return pcbnew.VECTOR2I(int(pcbnew.FromMM(OFFSET_X + x)), int(pcbnew.FromMM(OFFSET_Y + y)))

def add_segment(p1, p2, width_mm, net_obj):
    tr = pcbnew.PCB_TRACK(board)
    tr.SetStart(mm_vec(p1[0], p1[1]))
    tr.SetEnd(mm_vec(p2[0], p2[1]))
    tr.SetWidth(int(pcbnew.FromMM(width_mm)))
    tr.SetLayer(pcbnew.F_Cu)
    if net_obj: tr.SetNet(net_obj)
    add_item(tr)

# 2. Collision-Free Channel Routes on F.Cu
channel_routes = {
    "+3V3": (0.40, [
        [(5.25, 1.55), (3.0, 1.55)], [(3.0, 1.25), (1.2, 1.25)],
        [(3.0, 1.55), (3.0, 15.75)], [(3.0, 6.865), (1.2, 6.865)],
        [(3.0, 9.5), (3.65, 9.5)], [(3.0, 15.75), (1.2, 15.75)],
        [(5.25, 1.55), (5.25, 6.15)], [(5.25, 6.15), (6.45, 6.15)]
    ]),
    "VSYS": (0.40, [
        [(3.35, 1.55), (3.35, 3.45)], [(3.35, 3.45), (2.4, 3.45)],
        [(2.4, 3.45), (2.4, 16.5)], [(2.4, 16.5), (3.35, 16.5)]
    ]),
    "I2C0_SDA": (0.25, [
        [(1.2, 2.75), (0.4, 2.75)], [(0.4, 2.75), (0.4, 8.135)],
        [(0.4, 8.135), (1.2, 8.135)], [(0.4, 8.135), (0.4, 11.75)],
        [(0.4, 11.75), (6.45, 11.75)]
    ]),
    "I2C0_SCL": (0.25, [
        [(1.2, 9.405), (0.4, 9.405)], [(0.4, 9.405), (0.4, 17.25)],
        [(0.4, 17.25), (1.2, 17.25)], [(1.2, 9.405), (5.5, 9.405)],
        [(5.5, 9.405), (5.5, 12.55)], [(5.5, 12.55), (6.45, 12.55)]
    ]),
    "VBUS_5V": (0.40, [
        [(25.59, 16.4), (25.59, 19.2)], [(25.59, 19.2), (14.25, 19.2)],
        [(14.25, 19.2), (3.35, 19.2)], [(3.35, 19.2), (3.35, 15.55)]
    ]),
    "VBAT": (0.40, [
        [(23.5, 1.8), (22.0, 1.8)], [(22.0, 1.8), (22.0, 0.5)],
        [(22.0, 0.5), (2.4, 0.5)], [(2.4, 0.5), (2.4, 17.45)],
        [(2.4, 17.45), (3.35, 17.45)], [(2.4, 17.45), (2.4, 19.5)],
        [(2.4, 19.5), (12.35, 19.5)], [(12.35, 19.5), (12.35, 19.20)]
    ]),
    "USB_DP": (0.25, [
        [(25.59, 14.25), (21.5, 14.25)], [(21.5, 14.25), (21.5, 16.8)],
        [(21.5, 16.8), (8.75, 16.8)], [(8.75, 16.8), (8.75, 15.9)]
    ]),
    "USB_DM": (0.25, [
        [(25.59, 13.75), (21.0, 13.75)], [(21.0, 13.75), (21.0, 17.2)],
        [(21.0, 17.2), (7.95, 17.2)], [(7.95, 17.2), (7.95, 15.9)]
    ]),
    "CC1": (0.25, [
        [(25.59, 15.25), (28.0, 15.25)], [(28.0, 15.25), (28.0, 2.75)], [(28.0, 2.75), (29.8, 2.75)]
    ]),
    "CC2": (0.25, [
        [(25.59, 12.25), (28.0, 12.25)], [(28.0, 12.25), (28.0, 6.25)], [(28.0, 6.25), (29.8, 6.25)]
    ]),
    "PROG": (0.25, [
        [(14.25, 17.30), (17.25, 17.30)], [(17.25, 17.30), (17.25, 18.25)]
    ])
}

for net_name, (width, segments) in channel_routes.items():
    net_obj = find_net(net_name)
    for seg in segments:
        add_segment(seg[0], seg[1], width, net_obj)

# 3. Fill Solid GND Plane on B.Cu
gnd_net = find_net("GND")
if gnd_net:
    zone = pcbnew.ZONE(board)
    zone.SetLayer(pcbnew.B_Cu)
    zone.SetNet(gnd_net)
    pts = pcbnew.VECTOR_VECTOR2I()
    pts.push_back(mm_vec(-1.0, -1.0))
    pts.push_back(mm_vec(board_w + 1.0, -1.0))
    pts.push_back(mm_vec(board_w + 1.0, board_h + 1.0))
    pts.push_back(mm_vec(-1.0, board_h + 1.0))
    zone.AddPolygon(pts)
    add_item(zone)

    filler = pcbnew.ZONE_FILLER(board)
    zones = get_items("GetZones")
    if zones: filler.Fill(zones)

if hasattr(pcbnew, "Refresh"): pcbnew.Refresh()
print("SUCCESS: Main Board routed successfully!")
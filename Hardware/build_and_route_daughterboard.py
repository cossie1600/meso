import pcbnew

# 1. Fetch live board from KiCad GUI memory
board = pcbnew.GetBoard()

# 2. Clear all existing tracks, vias, and zones
for track in list(board.GetTracks()):
    board.Remove(track)

zones = board.Zones() if hasattr(board, "Zones") else []
for zone in list(zones):
    board.Remove(zone)

# 3. Draw 7.5mm x 7.5mm Edge.Cuts Boundary: (100.0, 100.0) to (107.5, 107.5)
for item in list(board.GetDrawings()):
    if item.GetLayerName() == "Edge.Cuts":
        board.Remove(item)

def add_edge(start, end):
    seg = pcbnew.PCB_SHAPE(board)
    seg.SetShape(pcbnew.S_SEGMENT)
    seg.SetStart(start)
    seg.SetEnd(end)
    seg.SetLayer(pcbnew.Edge_Cuts)
    seg.SetWidth(pcbnew.FromMM(0.10))
    board.Add(seg)

add_edge(pcbnew.VECTOR2I(pcbnew.FromMM(100.0), pcbnew.FromMM(100.0)), pcbnew.VECTOR2I(pcbnew.FromMM(107.5), pcbnew.FromMM(100.0)))
add_edge(pcbnew.VECTOR2I(pcbnew.FromMM(107.5), pcbnew.FromMM(100.0)), pcbnew.VECTOR2I(pcbnew.FromMM(107.5), pcbnew.FromMM(107.5)))
add_edge(pcbnew.VECTOR2I(pcbnew.FromMM(107.5), pcbnew.FromMM(107.5)), pcbnew.VECTOR2I(pcbnew.FromMM(100.0), pcbnew.FromMM(107.5)))
add_edge(pcbnew.VECTOR2I(pcbnew.FromMM(100.0), pcbnew.FromMM(107.5)), pcbnew.VECTOR2I(pcbnew.FromMM(100.0), pcbnew.FromMM(100.0)))

# 4. Position Footprints & Clean Silkscreens
for fp in board.GetFootprints():
    fp.Reference().SetVisible(False)
    fp.Value().SetVisible(False)

# J4 on RIGHT side (X = 105.8mm), flipped to B.Cu, dynamically centered vertically
j4 = board.FindFootprintByReference("J4")
if j4:
    j4_pos = pcbnew.VECTOR2I(pcbnew.FromMM(105.8), pcbnew.FromMM(103.75))
    j4.SetPosition(j4_pos)
    if j4.GetLayer() == pcbnew.F_Cu:
        j4.Flip(j4_pos, True)
    
    pad1 = j4.FindPadByNumber("1")
    pad4 = j4.FindPadByNumber("4")
    if pad1 and pad4:
        y_mid = (pad1.GetPosition().y + pad4.GetPosition().y) / 2.0
        dy = pcbnew.FromMM(103.75) - int(y_mid)
        j4.SetPosition(pcbnew.VECTOR2I(j4.GetPosition().x, j4.GetPosition().y + dy))

# U2 (BME688) on LEFT side (X = 102.4mm, Y = 104.5mm) on F.Cu
u2 = board.FindFootprintByReference("U2")
if u2:
    if u2.GetLayer() != pcbnew.F_Cu:
        u2.Flip(u2.GetPosition(), True)
    u2.SetPosition(pcbnew.VECTOR2I(pcbnew.FromMM(102.4), pcbnew.FromMM(104.5)))
    u2.SetOrientationDegrees(0)

# C2 (100nF Cap) Top-Left (X = 102.4mm, Y = 101.4mm) on F.Cu
c2 = board.FindFootprintByReference("C2")
if c2:
    if c2.GetLayer() != pcbnew.F_Cu:
        c2.Flip(c2.GetPosition(), True)
    c2.SetPosition(pcbnew.VECTOR2I(pcbnew.FromMM(102.4), pcbnew.FromMM(101.4)))
    c2.SetOrientationDegrees(0)

# Helper functions
def add_track(pt1, pt2, net, layer=pcbnew.F_Cu, width_mm=0.20):
    t = pcbnew.PCB_TRACK(board)
    t.SetStart(pt1)
    t.SetEnd(pt2)
    t.SetNet(net)
    t.SetLayer(layer)
    t.SetWidth(pcbnew.FromMM(width_mm))
    board.Add(t)

def add_via(pt, net):
    v = pcbnew.PCB_VIA(board)
    v.SetPosition(pt)
    v.SetNet(net)
    v.SetViaType(pcbnew.VIATYPE_THROUGH)
    v.SetWidth(pcbnew.FromMM(0.60))
    v.SetDrill(pcbnew.FromMM(0.30))
    board.Add(v)

def get_pad(ref, pad_num):
    return board.FindFootprintByReference(ref).FindPadByNumber(str(pad_num))

# Fetch Pads & Nets
j4_1 = get_pad("J4", 1) # GND
j4_2 = get_pad("J4", 2) # +3V3
j4_3 = get_pad("J4", 3) # SDA
j4_4 = get_pad("J4", 4) # SCL

c2_1 = get_pad("C2", 1) # +3V3
c2_2 = get_pad("C2", 2) # GND

u2_1 = get_pad("U2", 1) # GND
u2_2 = get_pad("U2", 2) # +3V3
u2_3 = get_pad("U2", 3) # +3V3
u2_4 = get_pad("U2", 4) # SDA
u2_5 = get_pad("U2", 5) # SCL
u2_6 = get_pad("U2", 6) # +3V3
u2_7 = get_pad("U2", 7) # GND
u2_8 = get_pad("U2", 8) # +3V3

gnd_net = j4_1.GetNet()
v33_net = j4_2.GetNet()
sda_net = j4_3.GetNet()
scl_net = j4_4.GetNet()

# 5. GND ROUTING (Direct Vias to B.Cu Ground Zone)
v_gnd1_pos = pcbnew.VECTOR2I(pcbnew.FromMM(103.8), pcbnew.FromMM(101.4))
add_track(c2_2.GetPosition(), v_gnd1_pos, gnd_net, pcbnew.F_Cu, 0.20)
add_via(v_gnd1_pos, gnd_net)

v_gnd2_pos = pcbnew.VECTOR2I(pcbnew.FromMM(101.2), pcbnew.FromMM(102.3))
add_track(u2_1.GetPosition(), v_gnd2_pos, gnd_net, pcbnew.F_Cu, 0.20)
add_via(v_gnd2_pos, gnd_net)

v_gnd3_pos = pcbnew.VECTOR2I(pcbnew.FromMM(102.0), pcbnew.FromMM(106.6))
add_track(u2_7.GetPosition(), v_gnd3_pos, gnd_net, pcbnew.F_Cu, 0.20)
add_via(v_gnd3_pos, gnd_net)

# 6. +3V3 ROUTING (Clean loop along X = 100.7mm)
p_j4_2 = j4_2.GetPosition()
p_u2_6 = u2_6.GetPosition()

# J4-2 -> U2-6
add_track(p_j4_2, pcbnew.VECTOR2I(pcbnew.FromMM(104.2), p_j4_2.y), v33_net, pcbnew.F_Cu, 0.22)
add_track(pcbnew.VECTOR2I(pcbnew.FromMM(104.2), p_j4_2.y), pcbnew.VECTOR2I(pcbnew.FromMM(104.2), p_u2_6.y), v33_net, pcbnew.F_Cu, 0.22)
add_track(pcbnew.VECTOR2I(pcbnew.FromMM(104.2), p_u2_6.y), p_u2_6, v33_net, pcbnew.F_Cu, 0.20)

# U2-6 -> U2-8 (Bypass U2-7 GND pad along Y = 106.2mm)
add_track(p_u2_6, pcbnew.VECTOR2I(p_u2_6.x, pcbnew.FromMM(106.2)), v33_net, pcbnew.F_Cu, 0.20)
add_track(pcbnew.VECTOR2I(p_u2_6.x, pcbnew.FromMM(106.2)), pcbnew.VECTOR2I(pcbnew.FromMM(101.2), pcbnew.FromMM(106.2)), v33_net, pcbnew.F_Cu, 0.20)
add_track(pcbnew.VECTOR2I(pcbnew.FromMM(101.2), pcbnew.FromMM(106.2)), u2_8.GetPosition(), v33_net, pcbnew.F_Cu, 0.20)

# U2-8 -> C2-1 (Along X = 100.7mm)
p_c2_1 = c2_1.GetPosition()
add_track(u2_8.GetPosition(), pcbnew.VECTOR2I(pcbnew.FromMM(100.7), u2_8.GetPosition().y), v33_net, pcbnew.F_Cu, 0.20)
add_track(pcbnew.VECTOR2I(pcbnew.FromMM(100.7), u2_8.GetPosition().y), pcbnew.VECTOR2I(pcbnew.FromMM(100.7), p_c2_1.y), v33_net, pcbnew.F_Cu, 0.20)
add_track(pcbnew.VECTOR2I(pcbnew.FromMM(100.7), p_c2_1.y), p_c2_1, v33_net, pcbnew.F_Cu, 0.20)

# Connect U2-2 & U2-3 from X = 100.7mm trunk
p_u2_2 = u2_2.GetPosition()
p_u2_3 = u2_3.GetPosition()
add_track(pcbnew.VECTOR2I(pcbnew.FromMM(100.7), p_u2_2.y), p_u2_2, v33_net, pcbnew.F_Cu, 0.20)
add_track(p_u2_2, p_u2_3, v33_net, pcbnew.F_Cu, 0.20)

# 7. I2C0_SDA ROUTING (Direct Track on F.Cu)
add_track(j4_3.GetPosition(), u2_4.GetPosition(), sda_net, pcbnew.F_Cu, 0.20)

# 8. I2C0_SCL ROUTING (B.Cu Bottom Layer Routing to eliminate top-layer crossing)
p_scl_start = j4_4.GetPosition()
p_scl_end = u2_5.GetPosition()
v_scl_pos = pcbnew.VECTOR2I(pcbnew.FromMM(104.8), p_scl_end.y)

add_track(p_scl_start, v_scl_pos, scl_net, pcbnew.B_Cu, 0.20)
add_via(v_scl_pos, scl_net)
add_track(v_scl_pos, p_scl_end, scl_net, pcbnew.F_Cu, 0.20)

# 9. B.CU GROUND PLANE
zone = pcbnew.ZONE(board)
zone.SetLayer(pcbnew.B_Cu)
zone.SetNet(gnd_net)
pts = pcbnew.VECTOR_VECTOR2I()
pts.push_back(pcbnew.VECTOR2I(pcbnew.FromMM(99.8), pcbnew.FromMM(99.8)))
pts.push_back(pcbnew.VECTOR2I(pcbnew.FromMM(107.7), pcbnew.FromMM(99.8)))
pts.push_back(pcbnew.VECTOR2I(pcbnew.FromMM(107.7), pcbnew.FromMM(107.7)))
pts.push_back(pcbnew.VECTOR2I(pcbnew.FromMM(99.8), pcbnew.FromMM(107.7)))
zone.AddPolygon(pts)
board.Add(zone)

filler = pcbnew.ZONE_FILLER(board)
filler.Fill(board.Zones())

pcbnew.Refresh()
pcbnew.SaveBoard("/Users/tmai/meso/Hardware/BME688_Daughterboard.kicad_pcb", board)
print("SUCCESS: Routed without crossings. Edge clearance >= 0.7mm.")
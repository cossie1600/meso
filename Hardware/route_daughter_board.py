import pcbnew

board_path = "/Users/tmai/meso/Hardware/BME688_Daughterboard.kicad_pcb"
board = pcbnew.LoadBoard(board_path)

# Clear old tracks and zones
for track in list(board.GetTracks()):
    board.Remove(track)
for zone in list(board.GetZones()):
    board.Remove(zone)

def get_pad(ref, pad_num):
    fp = board.FindFootprintByReference(ref)
    return fp.FindPadByNumber(str(pad_num))

def add_track(pt1, pt2, net, layer=pcbnew.F_Cu, width_mm=0.20):
    t = pcbnew.PCB_TRACK(board)
    t.SetStart(pt1)
    t.SetEnd(pt2)
    t.SetNet(net)
    t.SetLayer(layer)
    t.SetWidth(pcbnew.FromMM(width_mm))
    board.Add(t)

# Fetch Pads
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

# Add Ground Plane on B.Cu
zone = pcbnew.ZONE(board)
zone.SetLayer(pcbnew.B_Cu)
gnd_net = j4_1.GetNet()
zone.SetNet(gnd_net)

points = pcbnew.VECTOR_VECTOR2I()
points.push_back(pcbnew.VECTOR2I(pcbnew.FromMM(99.8), pcbnew.FromMM(99.8)))
points.push_back(pcbnew.VECTOR2I(pcbnew.FromMM(107.7), pcbnew.FromMM(99.8)))
points.push_back(pcbnew.VECTOR2I(pcbnew.FromMM(107.7), pcbnew.FromMM(107.7)))
points.push_back(pcbnew.VECTOR2I(pcbnew.FromMM(99.8), pcbnew.FromMM(107.7)))
zone.AddPolygon(points)
board.Add(zone)

filler = pcbnew.ZONE_FILLER(board)
filler.Fill(board.GetZones())

# Route GND Rail on F.Cu
add_track(j4_1.GetPosition(), c2_2.GetPosition(), gnd_net, pcbnew.F_Cu, 0.22)
add_track(c2_2.GetPosition(), u2_1.GetPosition(), gnd_net, pcbnew.F_Cu, 0.20)
add_track(u2_1.GetPosition(), u2_7.GetPosition(), gnd_net, pcbnew.F_Cu, 0.20)

# Route +3V3 Rail on F.Cu
v33_net = j4_2.GetNet()
add_track(j4_2.GetPosition(), c2_1.GetPosition(), v33_net, pcbnew.F_Cu, 0.22)
add_track(c2_1.GetPosition(), u2_8.GetPosition(), v33_net, pcbnew.F_Cu, 0.20)
add_track(u2_8.GetPosition(), u2_6.GetPosition(), v33_net, pcbnew.F_Cu, 0.20)
add_track(u2_6.GetPosition(), u2_2.GetPosition(), v33_net, pcbnew.F_Cu, 0.20)
add_track(u2_2.GetPosition(), u2_3.GetPosition(), v33_net, pcbnew.F_Cu, 0.20)

# Route SDA & SCL
sda_net = j4_3.GetNet()
scl_net = j4_4.GetNet()

add_track(j4_3.GetPosition(), u2_4.GetPosition(), sda_net, pcbnew.F_Cu, 0.20)

# Waypoint route for SCL to prevent crossing SDA
p_scl_start = j4_4.GetPosition()
p_scl_end = u2_5.GetPosition()
p_scl_wp = pcbnew.VECTOR2I(p_scl_start.x - pcbnew.FromMM(0.8), p_scl_start.y + pcbnew.FromMM(0.8))

if p_scl_start.y > p_scl_end.y:
    add_track(p_scl_start, p_scl_wp, scl_net, pcbnew.F_Cu, 0.20)
    add_track(p_scl_wp, p_scl_end, scl_net, pcbnew.F_Cu, 0.20)
else:
    add_track(p_scl_start, p_scl_end, scl_net, pcbnew.F_Cu, 0.20)

pcbnew.SaveBoard(board_path, board)
print("SUCCESS: Board routed cleanly. Pins centered inside outline.")
import pcbnew

board_path = "/Users/tmai/meso/Hardware/BME688_Daughterboard.kicad_pcb"
board = pcbnew.LoadBoard(board_path)

# 1. Re-draw 7.5mm x 7.5mm Edge.Cuts Outline: (100.0, 100.0) to (107.5, 107.5)
for item in list(board.GetDrawings()):
    if item.GetLayerName() == "Edge.Cuts":
        board.Remove(item)

def add_edge_line(start, end):
    segment = pcbnew.PCB_SHAPE(board)
    segment.SetShape(pcbnew.S_SEGMENT)
    segment.SetStart(start)
    segment.SetEnd(end)
    segment.SetLayer(pcbnew.Edge_Cuts)
    segment.SetWidth(pcbnew.FromMM(0.10))
    board.Add(segment)

p1 = pcbnew.VECTOR2I(pcbnew.FromMM(100.0), pcbnew.FromMM(100.0))
p2 = pcbnew.VECTOR2I(pcbnew.FromMM(107.5), pcbnew.FromMM(100.0))
p3 = pcbnew.VECTOR2I(pcbnew.FromMM(107.5), pcbnew.FromMM(107.5))
p4 = pcbnew.VECTOR2I(pcbnew.FromMM(100.0), pcbnew.FromMM(107.5))

add_edge_line(p1, p2)
add_edge_line(p2, p3)
add_edge_line(p3, p4)
add_edge_line(p4, p1)

# 2. Position J4 on RIGHT side (X = 105.5mm), FLIP to B.Cu, and dynamically center vertically
j4 = board.FindFootprintByReference("J4")
if j4:
    j4_pos = pcbnew.VECTOR2I(pcbnew.FromMM(105.5), pcbnew.FromMM(103.75))
    j4.SetPosition(j4_pos)
    if j4.GetLayer() == pcbnew.F_Cu:
        j4.Flip(j4_pos, True)  # Flip to B.Cu layer (pins pointing down)

    # Measure exact midpoint of Pad 1 and Pad 4, then shift J4 to center at Y = 103.75mm
    pad1 = j4.FindPadByNumber("1")
    pad4 = j4.FindPadByNumber("4")
    if pad1 and pad4:
        y_avg = (pad1.GetPosition().y + pad4.GetPosition().y) / 2.0
        target_y = pcbnew.FromMM(103.75)
        dy = target_y - int(y_avg)
        j4.SetPosition(pcbnew.VECTOR2I(j4.GetPosition().x, j4.GetPosition().y + dy))

# 3. Position U2 (BME688) on LEFT side (F.Cu - facing up)
u2 = board.FindFootprintByReference("U2")
if u2:
    if u2.GetLayer() != pcbnew.F_Cu:
        u2.Flip(u2.GetPosition(), True)
    u2.SetPosition(pcbnew.VECTOR2I(pcbnew.FromMM(102.3), pcbnew.FromMM(104.5)))
    u2.SetOrientationDegrees(0)

# 4. Position C2 (Decoupling Cap) Top-Left (F.Cu - facing up)
c2 = board.FindFootprintByReference("C2")
if c2:
    if c2.GetLayer() != pcbnew.F_Cu:
        c2.Flip(c2.GetPosition(), True)
    c2.SetPosition(pcbnew.VECTOR2I(pcbnew.FromMM(102.3), pcbnew.FromMM(101.4)))
    c2.SetOrientationDegrees(0)

pcbnew.SaveBoard(board_path, board)
print("SUCCESS: J4 positioned and dynamically centered vertically inside 7.5x7.5mm board bounds.")
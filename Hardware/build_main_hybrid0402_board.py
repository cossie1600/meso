import pcbnew

def exe():
    board = pcbnew.GetBoard()
    print("Targeting active PCB File for Bounded Placement in KiCad 10...")

    OFFSET_X = 100.0
    OFFSET_Y = 100.0
    BOARD_W = 21.50
    BOARD_H = 20.00

    # 1. Clear old drawings, tracks, and zones to prevent duplicate artifacts
    try:
        for t in list(board.GetTracks()):
            board.Delete(t)
        for z in list(board.Zones()):
            board.Delete(z)
        for d in list(board.GetDrawings()):
            if d.GetLayerName() == "Edge.Cuts":
                board.Delete(d)
    except Exception as e:
        print(f"Cleanup note: {e}")

    try:
        edge_layer = board.GetLayerID("Edge.Cuts")
    except Exception:
        edge_layer = pcbnew.Edge_Cuts

    # 2. Draw centered Edge.Cuts boundary rectangle at (100, 100)
    rect_pts = [
        pcbnew.VECTOR2I(pcbnew.FromMM(OFFSET_X), pcbnew.FromMM(OFFSET_Y)),
        pcbnew.VECTOR2I(pcbnew.FromMM(OFFSET_X + BOARD_W), pcbnew.FromMM(OFFSET_Y)),
        pcbnew.VECTOR2I(pcbnew.FromMM(OFFSET_X + BOARD_W), pcbnew.FromMM(OFFSET_Y + BOARD_H)),
        pcbnew.VECTOR2I(pcbnew.FromMM(OFFSET_X), pcbnew.FromMM(OFFSET_Y + BOARD_H)),
    ]

    for i in range(4):
        seg = pcbnew.PCB_SHAPE(board)
        if hasattr(pcbnew, 'SHAPE_T_SEGMENT'):
            seg.SetShape(pcbnew.SHAPE_T_SEGMENT)
        elif hasattr(pcbnew, 'S_SEGMENT'):
            seg.SetShape(pcbnew.S_SEGMENT)

        seg.SetStart(rect_pts[i])
        seg.SetEnd(rect_pts[(i + 1) % 4])
        seg.SetLayer(edge_layer)
        seg.SetWidth(pcbnew.FromMM(0.15))
        
        # KiCad 10 addition methods
        if hasattr(board, 'Add'):
            board.Add(seg)
        elif hasattr(board, 'AddNative'):
            board.AddNative(seg)

    def find_fp(ref):
        try:
            fp = board.FindFootprintByReference(ref)
            if fp:
                return fp
        except Exception:
            pass
        try:
            for fp in board.GetFootprints():
                if fp.GetReference() == ref:
                    return fp
        except Exception:
            pass
        return None

    def place_footprint(ref, x_mm, y_mm, angle_deg, flip_bottom=False):
        fp = find_fp(ref)
        if not fp:
            print(f"Warning: Component '{ref}' NOT FOUND on PCB canvas. Press F8 to sync!")
            return

        px = OFFSET_X + x_mm
        py = OFFSET_Y + y_mm
        pos_vec = pcbnew.VECTOR2I(pcbnew.FromMM(px), pcbnew.FromMM(py))

        is_on_bottom = (fp.GetLayer() == pcbnew.B_Cu)
        if flip_bottom and not is_on_bottom:
            fp.Flip(pos_vec, False)
        elif not flip_bottom and is_on_bottom:
            fp.Flip(pos_vec, False)

        fp.SetPosition(pos_vec)
        fp.SetOrientationDegrees(angle_deg)

    # 3. Option A Placement Coordinates (Collision-Free SMT JST Layout)
    place_footprint("U1", 8.00, 10.00, 0)                   # ESP32-C6 MINI-1 (Top)
    place_footprint("J1", 17.80, 13.50, 90)                 # USB-C (Right Edge)
    place_footprint("J2", 14.00, 4.50, 0, flip_bottom=True) # SMT JST-PH Connector (B.Cu)
    place_footprint("R3", 17.50, 6.50, 0)                   # CC1 Pull-down
    place_footprint("R4", 17.50, 8.00, 0)                   # CC2 Pull-down
    place_footprint("U3", 7.50, 18.20, 0)                   # MCP73831 Charger
    place_footprint("R5", 12.00, 18.20, 0)                  # PROG Resistor
    place_footprint("U4", 3.20, 2.80, 0)                    # AP2112K LDO
    place_footprint("C1", 6.20, 2.80, 90)                   # Decoupling Cap
    place_footprint("J3", 1.20, 10.50, 0)                   # 4-Pin Header
    place_footprint("R1", 1.20, 5.00, 90)                   # I2C SDA Pull-up
    place_footprint("R2", 1.20, 7.00, 90)                   # I2C SCL Pull-up
    place_footprint("D1", 2.50, 18.20, 180)                 # BAT54C Diode

    pcbnew.Refresh()
    print("build_main_hybrid0402_board.py: Option A SMT placement complete.")

exe()
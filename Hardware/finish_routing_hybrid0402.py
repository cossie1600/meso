import pcbnew

def exe():
    board = pcbnew.GetBoard()
    print("Generating dynamic ground pour on B.Cu...")

    b_cu_layer = pcbnew.B_Cu

    # Clear old tracks and zones
    try:
        for t in list(board.GetTracks()):
            board.Remove(t)
        for z in list(board.Zones()):
            board.Remove(z)
    except Exception:
        pass

    def get_net(net_name):
        net = board.FindNet(net_name)
        if not net or net.GetNetname() == "":
            net = board.FindNet("/" + net_name)
        return net

    # Find board bounding box from Edge.Cuts
    box = board.GetBoardEdgesBoundingBox()

    # Create Ground Zone on B.Cu
    gnd_net = get_net("GND")
    zone = pcbnew.ZONE(board)
    zone.SetLayer(b_cu_layer)
    if gnd_net:
        zone.SetNet(gnd_net)

    outline = pcbnew.SHAPE_LINE_CHAIN()
    outline.Append(pcbnew.VECTOR2I(box.GetLeft(), box.GetTop()))
    outline.Append(pcbnew.VECTOR2I(box.GetRight(), box.GetTop()))
    outline.Append(pcbnew.VECTOR2I(box.GetRight(), box.GetBottom()))
    outline.Append(pcbnew.VECTOR2I(box.GetLeft(), box.GetBottom()))
    outline.SetClosed(True)

    try:
        zone.AddPolygon(outline)
    except Exception:
        try:
            zone.Outline().AddOutline(outline)
        except Exception:
            pass

    board.Add(zone)

    # Refill zones
    try:
        filler = pcbnew.ZONE_FILLER(board)
        filler.Fill(board.Zones())
    except Exception:
        pass

    pcbnew.Refresh()
    print("Ground zone successfully generated.")

exe()
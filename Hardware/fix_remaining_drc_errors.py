import pcbnew

def exe():
    board = pcbnew.GetBoard()
    print("Applying Targeted DRC Fixes (Zero Purge)...")

    f_cu = pcbnew.F_Cu
    b_cu = pcbnew.B_Cu

    def get_net(net_name):
        net = board.FindNet(net_name)
        if not net or net.GetNetname() == "":
            net = board.FindNet("/" + net_name)
        return net

    gnd_net = get_net("GND")
    v33_net = get_net("+3V3")

    def add_via(x_mm, y_mm, net):
        via = pcbnew.PCB_VIA(board)
        via.SetPosition(pcbnew.VECTOR2I(pcbnew.FromMM(x_mm), pcbnew.FromMM(y_mm)))
        via.SetWidth(pcbnew.FromMM(0.60))
        via.SetDrill(pcbnew.FromMM(0.30))
        if net:
            via.SetNet(net)
        board.Add(via)

    def add_seg(x1, y1, x2, y2, layer, net, width=0.20):
        track = pcbnew.PCB_TRACK(board)
        track.SetStart(pcbnew.VECTOR2I(pcbnew.FromMM(x1), pcbnew.FromMM(y1)))
        track.SetEnd(pcbnew.VECTOR2I(pcbnew.FromMM(x2), pcbnew.FromMM(y2)))
        track.SetLayer(layer)
        track.SetWidth(pcbnew.FromMM(width))
        if net:
            track.SetNet(net)
        board.Add(track)

    # 1. FIX GND UNCONNECTED ISLANDS WITH TARGETED VIAS
    add_via(104.60, 106.80, gnd_net)
    add_via(105.8625, 117.50, gnd_net)

    # 2. FIX GND TRACK GAP (104.422, 103.175) -> (101.80, 102.00)
    # Detour slightly north (Y = 101.20 mm) to clear VSYS and +3V3 vias
    add_seg(104.422, 103.175, 104.422, 101.200, f_cu, gnd_net, width=0.18)
    add_seg(104.422, 101.200, 101.800, 101.200, f_cu, gnd_net, width=0.18)
    add_seg(101.800, 101.200, 101.800, 102.000, f_cu, gnd_net, width=0.18)

    # 3. FIX +3V3 DISCONNECT AT (103.3375, 105.4875)
    # Bridge B.Cu to F.Cu with a dedicated via right at the endpoint
    add_via(103.3375, 105.4875, v33_net)

    # REFILL ZONES
    try:
        filler = pcbnew.ZONE_FILLER(board)
        filler.Fill(board.Zones())
    except Exception as e:
        print(f"Refill note: {e}")

    pcbnew.Refresh()
    print("Minimal patch complete!")

exe()
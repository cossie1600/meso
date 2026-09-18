import os
import pcbnew
from pcbnew import EXCELLON_WRITER

def mm(val):
    return pcbnew.FromMM(val) if hasattr(pcbnew, 'FromMM') else int(val * 1000000)

def make_point(x, y):
    if hasattr(pcbnew, 'VECTOR2I'):
        return pcbnew.VECTOR2I(int(x), int(y))
    return pcbnew.wxPoint(int(x), int(y))

board = pcbnew.GetBoard() if pcbnew.GetBoard() else pcbnew.BOARD()

# Wipe old board contents to prevent duplicate selection issues
for item in list(board.GetFootprints()):
    board.Remove(item)
for item in list(board.GetDrawings()):
    board.Remove(item)

main_cx, main_cy = mm(100), mm(100)
sub_cx, sub_cy = mm(150), mm(100)

main_w, main_h = mm(45), mm(18)
sub_w, sub_h = mm(12), mm(12)

# Draw Board Outlines
def add_rect_outline(board_obj, center_x, center_y, width, height):
    half_w, half_h = width / 2, height / 2
    pts = [
        (center_x - half_w, center_y - half_h),
        (center_x + half_w, center_y - half_h),
        (center_x + half_w, center_y + half_h),
        (center_x - half_w, center_y + half_h)
    ]
    for i in range(4):
        seg = pcbnew.PCB_SHAPE(board_obj)
        seg.SetShape(pcbnew.S_SEGMENT)
        seg.SetLayer(pcbnew.Edge_Cuts)
        seg.SetStart(make_point(pts[i][0], pts[i][1]))
        seg.SetEnd(make_point(pts[(i + 1) % 4][0], pts[(i + 1) % 4][1]))
        seg.SetWidth(mm(0.1))
        board_obj.Add(seg)

def create_custom_footprint(name, pads_config):
    fp = pcbnew.FOOTPRINT(board)
    fp.SetValue(name)
    fp.SetReference(name[0])
    
    for pad_num, pos_x, pos_y, size_x, size_y, net_name in pads_config:
        pad = pcbnew.PAD(fp)
        pad.SetNumber(str(pad_num))
        pad.SetShape(pcbnew.PAD_SHAPE_RECT)
        pad.SetAttribute(pcbnew.PAD_ATTRIB_SMD)
        
        # Force layer explicitly to Top Copper
        pad.SetLayer(pcbnew.F_Cu)
        pad.SetPosition(make_point(pos_x, pos_y))
        pad.SetSize(make_point(size_x, size_y))
        
        if net_name:
            net = board.FindNet(net_name)
            if not net:
                net = pcbnew.NETINFO_ITEM(board, net_name)
                board.Add(net)
            pad.SetNet(net)
            
        fp.Add(pad)
        
    return fp

# 1. Main Board Outline (18mm x 45mm)
add_rect_outline(board, main_cx, main_cy, main_w, main_h)

# 2. Main Board XIAO ESP32-C3 Pads (Explicitly mapped to nets)
xiao_pads = [
    (1, main_cx - mm(10), main_cy - mm(7.62) + mm(2.54*0), mm(1.6), mm(2.0), ""),
    (2, main_cx - mm(10), main_cy - mm(7.62) + mm(2.54*1), mm(1.6), mm(2.0), ""),
    (3, main_cx - mm(10), main_cy - mm(7.62) + mm(2.54*2), mm(1.6), mm(2.0), ""),
    (4, main_cx - mm(10), main_cy - mm(7.62) + mm(2.54*3), mm(1.6), mm(2.0), ""),
    (5, main_cx - mm(10), main_cy - mm(7.62) + mm(2.54*4), mm(1.6), mm(2.0), "SDA"),
    (6, main_cx - mm(10), main_cy - mm(7.62) + mm(2.54*5), mm(1.6), mm(2.0), "SCL"),
    (7, main_cx - mm(10), main_cy - mm(7.62) + mm(2.54*6), mm(1.6), mm(2.0), ""),
    (8, main_cx + mm(0), main_cy - mm(7.62) + mm(2.54*0), mm(1.6), mm(2.0), ""),
    (9, main_cx + mm(0), main_cy - mm(7.62) + mm(2.54*1), mm(1.6), mm(2.0), "GND"),
    (10, main_cx + mm(0), main_cy - mm(7.62) + mm(2.54*2), mm(1.6), mm(2.0), "3V3"),
    (11, main_cx + mm(0), main_cy - mm(7.62) + mm(2.54*3), mm(1.6), mm(2.0), ""),
    (12, main_cx + mm(0), main_cy - mm(7.62) + mm(2.54*4), mm(1.6), mm(2.0), ""),
    (13, main_cx + mm(0), main_cy - mm(7.62) + mm(2.54*5), mm(1.6), mm(2.0), ""),
    (14, main_cx + mm(0), main_cy - mm(7.62) + mm(2.54*6), mm(1.6), mm(2.0), "")
]
board.Add(create_custom_footprint("XIAO_ESP32C3", xiao_pads))

# 3. Main Board JST-SH Connector
jst_pads = [
    (1, main_cx - mm(18), main_cy - mm(0.5), mm(0.6), mm(1.55), "3V3"),
    (2, main_cx - mm(18), main_cy + mm(0.5), mm(0.6), mm(1.55), "GND")
]
board.Add(create_custom_footprint("JST_SH_2P", jst_pads))

# 4. Main Board Edge Joint Tabs
main_right_edge = main_cx + main_w / 2
main_joint_pads = [
    ("3V3", main_right_edge - mm(0.8), main_cy - mm(3.0), mm(1.6), mm(1.2), "3V3"),
    ("GND", main_right_edge - mm(0.8), main_cy - mm(1.0), mm(1.6), mm(1.2), "GND"),
    ("SDA", main_right_edge - mm(0.8), main_cy + mm(1.0), mm(1.6), mm(1.2), "SDA"),
    ("SCL", main_right_edge - mm(0.8), main_cy + mm(3.0), mm(1.6), mm(1.2), "SCL")
]
board.Add(create_custom_footprint("JOINT_MAIN", main_joint_pads))

# 5. Perpendicular Sub-PCB Outline (12mm x 12mm)
add_rect_outline(board, sub_cx, sub_cy, sub_w, sub_h)

# 6. BME688 Sensor Pads
bme_pads = [
    (1, sub_cx - mm(1.2), sub_cy - mm(1.2), mm(0.5), mm(0.5), "GND"),
    (2, sub_cx - mm(1.2), sub_cy - mm(0.4), mm(0.5), mm(0.5), "3V3"),
    (3, sub_cx - mm(1.2), sub_cy + mm(0.4), mm(0.5), mm(0.5), "SDA"),
    (4, sub_cx - mm(1.2), sub_cy + mm(1.2), mm(0.5), mm(0.5), "SCL"),
    (5, sub_cx + mm(1.2), sub_cy + mm(1.2), mm(0.5), mm(0.5), "GND"),
    (6, sub_cx + mm(1.2), sub_cy + mm(0.4), mm(0.5), mm(0.5), "3V3"),
    (7, sub_cx + mm(1.2), sub_cy - mm(0.4), mm(0.5), mm(0.5), "GND"),
    (8, sub_cx + mm(1.2), sub_cy - mm(1.2), mm(0.5), mm(0.5), "3V3")
]
board.Add(create_custom_footprint("BME688", bme_pads))

# 7. Sub-PCB Castellated Edge Tabs
sub_left_edge = sub_cx - sub_w / 2
sub_joint_pads = [
    ("3V3", sub_left_edge + mm(0.8), sub_cy - mm(3.0), mm(1.6), mm(1.2), "3V3"),
    ("GND", sub_left_edge + mm(0.8), sub_cy - mm(1.0), mm(1.6), mm(1.2), "GND"),
    ("SDA", sub_left_edge + mm(0.8), sub_cy + mm(1.0), mm(1.6), mm(1.2), "SDA"),
    ("SCL", sub_left_edge + mm(0.8), sub_cy + mm(3.0), mm(1.6), mm(1.2), "SCL")
]
board.Add(create_custom_footprint("JOINT_SUB", sub_joint_pads))

pcbnew.Refresh()

# Save & Export Output
output_dir = os.path.join(os.path.expanduser("~"), "KiCad_Gerbers_Output")
os.makedirs(output_dir, exist_ok=True)
save_path = os.path.join(output_dir, "Main_Perpendicular_Board.kicad_pcb")

pcbnew.SaveBoard(save_path, board)

plot_controller = pcbnew.PLOT_CONTROLLER(board)
plot_options = plot_controller.GetPlotOptions()
plot_options.SetOutputDirectory(output_dir)
plot_options.SetPlotFrameRef(False)

for attr, val in [('SetDefaultLineWidth', mm(0.1)), ('SetLineWidth', mm(0.1))]:
    if hasattr(plot_options, attr):
        getattr(plot_options, attr)(val)
        break

plot_options.SetAutoScale(False)
plot_options.SetScale(1)
plot_options.SetMirror(False)
plot_options.SetUseGerberAttributes(True)

layers = [
    ("F_Cu", pcbnew.F_Cu, "Top Copper"),
    ("B_Cu", pcbnew.B_Cu, "Bottom Copper"),
    ("F_SilkS", pcbnew.F_SilkS, "Top Silk"),
    ("B_SilkS", pcbnew.B_SilkS, "Bottom Silk"),
    ("F_Mask", pcbnew.F_Mask, "Top Mask"),
    ("B_Mask", pcbnew.B_Mask, "Bottom Mask"),
    ("Edge_Cuts", pcbnew.Edge_Cuts, "Board Outline")
]

for layer_name, layer_id, description in layers:
    plot_controller.SetLayer(layer_id)
    plot_controller.OpenPlotfile(layer_name, pcbnew.PLOT_FORMAT_GERBER, description)
    plot_controller.PlotLayer()

plot_controller.ClosePlot()
print("Board rebuilt on F.Cu with assigned nets!")
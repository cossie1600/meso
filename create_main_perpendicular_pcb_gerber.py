import os
import pcbnew
from pcbnew import EXCELLON_WRITER

# Helper for KiCad millimeter conversion
def mm(val):
    return pcbnew.FromMM(val) if hasattr(pcbnew, 'FromMM') else int(val * 1000000)

# Helper for point creation across KiCad versions
def make_point(x, y):
    if hasattr(pcbnew, 'VECTOR2I'):
        return pcbnew.VECTOR2I(int(x), int(y))
    return pcbnew.wxPoint(int(x), int(y))

# 1. Bind to Active Board in PCB Editor Workspace
board = pcbnew.GetBoard() if pcbnew.GetBoard() else pcbnew.BOARD()

main_cx, main_cy = mm(100), mm(100)
sub_cx, sub_cy = mm(150), mm(100)

# Helper: Draw Rectangular Perimeter using PCB_SHAPE Segments
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

# Helper: Create Custom Footprints Programmatically
def create_custom_footprint(name, pads_config, layer):
    fp = pcbnew.FOOTPRINT(board)
    fp.SetValue(name)
    fp.SetReference(name[0])
    
    for pad_num, pos_x, pos_y, size_x, size_y in pads_config:
        pad = pcbnew.PAD(fp)
        pad.SetNumber(str(pad_num))
        pad.SetShape(pcbnew.PAD_SHAPE_RECT)
        pad.SetAttribute(pcbnew.PAD_ATTRIB_SMD)
        pad.SetLayer(layer)  # Direct layer assignment for KiCad 10
        pad.SetPosition(make_point(pos_x, pos_y))
        pad.SetSize(make_point(size_x, size_y))
        fp.Add(pad)
        
    return fp

# 2. Draw Main Board Outline (18mm x 45mm)
add_rect_outline(board, main_cx, main_cy, mm(45), mm(18))

# 3. Add Seeed XIAO ESP32-C3 Pads (14 SMD Pads)
xiao_pads = []
for i in range(7):
    xiao_pads.append((i+1, main_cx - mm(10), main_cy - mm(7.62) + mm(2.54*i), mm(1.6), mm(2.0)))
for i in range(7):
    xiao_pads.append((i+8, main_cx + mm(0), main_cy - mm(7.62) + mm(2.54*i), mm(1.6), mm(2.0)))

xiao_fp = create_custom_footprint("XIAO_ESP32C3", xiao_pads, pcbnew.F_Cu)
board.Add(xiao_fp)

# 4. Add JST-SH Connector Pads
jst_pads = [
    (1, main_cx - mm(18), main_cy - mm(0.5), mm(0.6), mm(1.55)),
    (2, main_cx - mm(18), main_cy + mm(0.5), mm(0.6), mm(1.55))
]
jst_fp = create_custom_footprint("JST_SH_2P", jst_pads, pcbnew.F_Cu)
board.Add(jst_fp)

# 5. Draw Perpendicular Sub-PCB Outline (12mm x 12mm)
add_rect_outline(board, sub_cx, sub_cy, mm(12), mm(12))

# 6. Add BME688 LGA-8 Sensor Pads (8 SMD Pads)
bme_pads = [
    (1, sub_cx - mm(1.2), sub_cy - mm(1.2), mm(0.5), mm(0.5)),
    (2, sub_cx - mm(1.2), sub_cy - mm(0.4), mm(0.5), mm(0.5)),
    (3, sub_cx - mm(1.2), sub_cy + mm(0.4), mm(0.5), mm(0.5)),
    (4, sub_cx - mm(1.2), sub_cy + mm(1.2), mm(0.5), mm(0.5)),
    (5, sub_cx + mm(1.2), sub_cy + mm(1.2), mm(0.5), mm(0.5)),
    (6, sub_cx + mm(1.2), sub_cy + mm(0.4), mm(0.5), mm(0.5)),
    (7, sub_cx + mm(1.2), sub_cy - mm(0.4), mm(0.5), mm(0.5)),
    (8, sub_cx + mm(1.2), sub_cy - mm(1.2), mm(0.5), mm(0.5)),
]
bme_fp = create_custom_footprint("BME688", bme_pads, pcbnew.F_Cu)
board.Add(bme_fp)

# 7. Refresh Viewport & Save Board File
pcbnew.Refresh()

output_dir = os.path.join(os.path.expanduser("~"), "KiCad_Gerbers_Output")
os.makedirs(output_dir, exist_ok=True)
save_path = os.path.join(output_dir, "Main_Perpendicular_Board.kicad_pcb")

pcbnew.SaveBoard(save_path, board)

# 8. Automatic Gerber & Drill File Export
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

# Generate Drill File
try:
    drill_writer = EXCELLON_WRITER(board)
    if hasattr(drill_writer, 'SetMapFileFormat'):
        drill_writer.SetMapFileFormat(pcbnew.PLOT_FORMAT_GERBER)
    if hasattr(drill_writer, 'SetOutputDirectory'):
        drill_writer.SetOutputDirectory(output_dir)
    drill_writer.CreateDrillandMapFilesSet(output_dir, True, False)
except Exception:
    pass

print("Script executed successfully! PCB and Gerbers created.")

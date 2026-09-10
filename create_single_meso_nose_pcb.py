import os
import pcbnew
from pcbnew import GERBER_WRITER, EXCELLON_WRITER

# Helper for KiCad millimeter conversion
def mm(val):
    return pcbnew.FromMM(val) if hasattr(pcbnew, 'FromMM') else int(val * 1000000)

# Helper for point creation across KiCad versions
def make_point(x, y):
    if hasattr(pcbnew, 'VECTOR2I'):
        return pcbnew.VECTOR2I(int(x), int(y))
    return pcbnew.wxPoint(int(x), int(y))

# 1. Initialize Board
board = pcbnew.GetBoard() if pcbnew.GetBoard() else pcbnew.BOARD()

# System path to KiCad 3D models on macOS
KICAD_3D_DIR = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/3dmodels/"

# Helper to attach 3D model paths to footprints
def add_3d_model(footprint, relative_path):
    try:
        model = pcbnew.FP_3DMODEL()
        model.m_Filename = os.path.join(KICAD_3D_DIR, relative_path)
        footprint.Models().append(model)
    except Exception:
        pass

# Robust footprint loader using KiCad Plugin Manager
def load_footprint(lib_nickname, fp_name):
    try:
        plugin = pcbnew.IO_MGR.PluginFind(pcbnew.IO_MGR.KICAD_SELECTION)
        lib_path = pcbnew.GFootprintTable().FindRow(lib_nickname).GetFullURI()
        return plugin.FootprintLoad(lib_path, fp_name)
    except Exception:
        pass

    fp = pcbnew.FOOTPRINT(board)
    fp.SetFPID(pcbnew.LIB_ID(str(lib_nickname), str(fp_name)))
    return fp

# Center point at (100mm, 100mm)
center_x = mm(100)
center_y = mm(100)

# 2. Draw 22mm Circular Edge Cut
radius = mm(11)
circle = pcbnew.PCB_SHAPE(board)
circle.SetShape(pcbnew.S_CIRCLE)
circle.SetLayer(pcbnew.Edge_Cuts)
circle.SetStart(make_point(center_x, center_y)) # Center
circle.SetEnd(make_point(center_x + radius, center_y)) # Edge point
circle.SetWidth(mm(0.1))
board.Add(circle)

# 3. Add BME688 (Top Layer, Centered) + 3D Model
bme = load_footprint("Package_LGA", "Bosch_LGA-8_3x3mm_P0.8mm-Clockwise")
bme.SetPosition(make_point(center_x, center_y))
bme.SetLayer(pcbnew.F_Cu)
add_3d_model(bme, "Package_LGA.3dshapes/Bosch_LGA-8_3x3mm_P0.8mm-Clockwise.wrl")
board.Add(bme)

# 4. Add Seeed XIAO ESP32-C3 (Bottom Layer, Top-Half) + 3D Model
xiao = load_footprint("Module", "Seeed_XIAO_ESP32C3")
xiao.SetPosition(make_point(center_x, center_y - mm(3)))
xiao.SetLayer(pcbnew.B_Cu)
add_3d_model(xiao, "Module.3dshapes/Seeed_XIAO_ESP32C3.wrl")
board.Add(xiao)

# 5. Add Vertical JST-SH 2-Pin Header (Bottom Layer, Bottom-Half) + 3D Model
jst = load_footprint("Connector_JST", "JST_SH_BM02B-SRSS-TB_1x02-1MP_P1.00mm_Vertical")
jst.SetPosition(make_point(center_x, center_y + mm(6)))
jst.SetLayer(pcbnew.B_Cu)
add_3d_model(jst, "Connector_JST.3dshapes/JST_SH_BM02B-SRSS-TB_1x02-1MP_P1.00mm_Vertical.wrl")
board.Add(jst)

# Refresh Viewport (If running inside GUI)
pcbnew.Refresh()

# 6. Save Board File
output_dir = os.path.join(os.path.expanduser("~"), "KiCad_Gerbers_Output")
os.makedirs(output_dir, exist_ok=True)
save_path = os.path.join(output_dir, "single_meso_nose.kicad_pcb")

pcbnew.SaveBoard(save_path, board)

# 7. Generate Gerber & Drill Files
plot_controller = pcbnew.PLOT_CONTROLLER(board)
plot_options = plot_controller.GetPlotOptions()
plot_options.SetOutputDirectory(output_dir)
plot_options.SetPlotFrameRef(False)

# Version-agnostic option setters
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
drill_writer = EXCELLON_WRITER(board)
drill_writer.SetMapFileFormat(pcbnew.PLOT_FORMAT_GERBER)

if hasattr(drill_writer, 'SetOutputDirectory'):
    drill_writer.SetOutputDirectory(output_dir)

drill_writer.CreateDrillandMapFilesSet(output_dir, True, False)

print("Successfully generated 22mm Pendant PCB layout!")
print(f"Board saved to: {save_path}")
print(f"Gerbers exported to: {output_dir}")
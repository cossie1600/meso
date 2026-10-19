from build123d import *
from ocp_vscode import show

# ==============================================================================
# PARAMETRIC JEWELRY CONSTANTS (mm)
# ==============================================================================
PCB_X = 28.0
PCB_Y = 25.0
PCB_Z = 1.6
CLEARANCE = 0.35  # Thermal expansion & assembly fit tolerance

# Daughterboard & Port Dimensions from PCB Layout
SENSOR_Z = 12.5   # Vertical BME688 daughterboard height
USBC_W = 9.5
USBC_H = 3.5

WALL = 2.0
CORNER_RAD = 3.5
BAIL_RAD = 3.2

# Inner Cavity Dimensions
cav_x = PCB_X + (CLEARANCE * 2)
cav_y = PCB_Y + (CLEARANCE * 2)
cav_z = SENSOR_Z + PCB_Z + (CLEARANCE * 2)

# ==============================================================================
# MODEL GENERATION
# ==============================================================================
with BuildPart() as pendant:
    # 1. Outer Sculpted Shell Body
    Box(cav_x + (WALL * 2), cav_y + (WALL * 2), cav_z + (WALL * 2))
    fillet(pendant.edges().filter_by(Axis.Z), CORNER_RAD)
    
    # 2. Internal Board Cavity
    Box(cav_x, cav_y, cav_z, mode=Mode.SUBTRACT)
    
    # 3. USB-C Opening at Bottom Face
    with Locations(Location((0, -(cav_y/2 + WALL), -cav_z/4))):
        Box(USBC_W, WALL * 3, USBC_H, mode=Mode.SUBTRACT)
        
    # 4. Air Intake Filigree Vents (Front Face for BME688 Sensor)
    with Locations(Location((0, 0, cav_z/4))):
        for x_off in [-6.0, 0.0, 6.0]:
         with Locations(Location((x_off, 0, 0))):
            # Creates a 3D slot opening straight through the wall thickness
            Box(8.0, WALL * 3, 1.6, mode=Mode.SUBTRACT)

    # 5. Top Necklace Attachment Bail Loop
    with Locations(Location((0, 0, (cav_z/2 + WALL)))):
        with BuildSketch(Plane.XZ):
            Circle(BAIL_RAD)
            Circle(BAIL_RAD - 1.2, mode=Mode.SUBTRACT)
        extrude(amount=WALL)

# Render live in VS Code OCP Viewer
show(pendant)

# Export direct production STEP file for lost-wax 3D casting
export_step(pendant.part, "functional_pendant.step")

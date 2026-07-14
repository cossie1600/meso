import os
import shutil
import glob
import zipfile

def create_ipa():
    # 1. Define paths
    project_name = "MesoSensorDashboard"
    desktop = os.path.expanduser("~/Desktop")
    derived_data_path = os.path.expanduser("~/Library/Developer/Xcode/DerivedData")
    
    # 2. Search for the compiled .app file
    search_pattern = os.path.join(derived_data_path, f"{project_name}-*", "Build", "Products", "Debug-iphoneos", f"{project_name}.app")
    matching_paths = glob.glob(search_pattern)
    
    if not matching_paths:
        print("❌ Error: Could not find compiled app in DerivedData.")
        print("👉 Make sure you ran 'Product > Build' or 'Product > Archive' in Xcode targeting a physical device first!")
        return
        
    app_path = matching_paths[0]
    print(f"📦 Found compiled app at: {app_path}")
    
    # 3. Create clean local Payload directory
    payload_dir = os.path.abspath("Payload")
    if os.path.exists(payload_dir):
        shutil.rmtree(payload_dir)
    os.makedirs(payload_dir)
    
    # 4. Copy the .app bundle into Payload folder
    print("🚚 Copying app binary into Payload container...")
    destination_path = os.path.join(payload_dir, f"{project_name}.app")
    shutil.copytree(app_path, destination_path)
    
    # 5. Compress into final .ipa package directly to your Desktop
    ipa_output_path = os.path.join(desktop, f"{project_name}.ipa")
    print(f"⚡ Compressing into IPA package on your Desktop...")
    
    with zipfile.ZipFile(ipa_output_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(payload_dir):
            for file in files:
                file_path = os.path.join(root, file)
                # Maintain internal structure relative to the execution folder
                arcname = os.path.relpath(file_path, os.path.dirname(payload_dir))
                zipf.write(file_path, arcname)
                
    # 6. Cleanup working files
    shutil.rmtree(payload_dir)
    print(f"🎉 Success! Final installable package saved to: {ipa_output_path}")

if __name__ == "__main__":
    create_ipa()
    
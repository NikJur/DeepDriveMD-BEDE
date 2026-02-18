import os
import re
import sys

# ------------------------------------------------------------------------------
# Auto-Patcher for MD-tools on PowerPC
# ------------------------------------------------------------------------------
# This script applies a global search-and-replace to fix OpenMM unit errors.
# It targets the specific syntax 'var * u.unit' causing SWIG TypeErrors.
# ------------------------------------------------------------------------------

def patch_file():
    # 1. Locate the target file
    script_dir = os.path.dirname(os.path.abspath(__file__))
    # Adjust path to find MD-tools relative to DeepDriveMD-BEDE/bede_env_setup/
    target_path = os.path.abspath(os.path.join(script_dir, "../../MD-tools/mdtools/openmm/sim.py"))

    print(f"Targeting: {target_path}")

    if not os.path.exists(target_path):
        print(f"Error: Could not find sim.py at {target_path}")
        sys.exit(1)

    with open(target_path, 'r') as f:
        content = f.read()

    # --------------------------------------------------------------------------
    # STEP 1: Inject the Helper Lambda
    # --------------------------------------------------------------------------
    # We inject the helper function once at the top of the file (after imports)
    if "_strip_val =" not in content:
        import_pattern = r"(import openmm\.unit as u)"
        helper_code = "\n\n# BEDE PATCH: Helper to strip units\n_strip_val = lambda x: x._value if hasattr(x, '_value') else x\n"

        if re.search(import_pattern, content):
            content = re.sub(import_pattern, r"\1" + helper_code, content, count=1)
            print("   -> Injected '_strip_val' helper function.")

    # --------------------------------------------------------------------------
    # STEP 2: Aggressive Global Replacement
    # --------------------------------------------------------------------------
    # We replace the problematic patterns everywhere in the file.
    # This covers Integrators, Velocties, and any other usage.

    replacements = [
        # Target: temperature_kelvin * u.kelvin
        (r"temperature_kelvin\s*\*\s*u\.kelvin", "float(_strip_val(temperature_kelvin))"),

        # Target: heat_bath_friction_coef / u.picosecond
        (r"heat_bath_friction_coef\s*/\s*u\.picosecond", "float(_strip_val(heat_bath_friction_coef))"),

        # Target: dt_ps * u.picosecond
        (r"dt_ps\s*\*\s*u\.picosecond", "float(_strip_val(dt_ps))")
    ]

    match_count = 0
    for pattern, replacement in replacements:
        # Use regex to find and count matches before replacing
        matches = re.findall(pattern, content)
        if matches:
            match_count += len(matches)
            content = re.sub(pattern, replacement, content)
            print(f"   -> Replaced {len(matches)} instance(s) of '{pattern}'")

    # --------------------------------------------------------------------------
    # STEP 3: Verify & Save
    # --------------------------------------------------------------------------
    # Check if the velocity line specifically was fixed
    velocity_check = "float(_strip_val(temperature_kelvin)), random.randint"

    if velocity_check in content:
        print("Verified: Velocity initialization is patched.")
    else:
        print("ARNING: Velocity initialization might NOT be patched. Check file manually.")

    with open(target_path, 'w') as f:
        f.write(content)
    print(f"Success: MD-tools patched ({match_count} changes applied). Continue installation following README file.")

if __name__ == "__main__":
    patch_file()
  

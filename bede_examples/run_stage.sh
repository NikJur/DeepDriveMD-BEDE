#!/bin/bash
# ------------------------------------------------------------------------------
# DeepDriveMD Wrapper for Bede (PowerPC ppc64le)
# ------------------------------------------------------------------------------
# This script handles the "Dual-Environment" strategy required for PowerPC.
# It hot-swaps Conda environments based on the pipeline stage.
#
# USAGE:
# 1. Update the 'USER_PROJECT_ROOT' variable below to your project folder.
# 2. Ensure the two conda environments (ddmd_openmm, ddmd_keras) are installed.
# ------------------------------------------------------------------------------

# === CONFIGURATION: UPDATE THESE PATHS ===
# The base directory in your 'sources'
#USER_PROJECT_ROOT="/nobackup/projects/<project_code>/<user_name>/sources"
USER_PROJECT_ROOT="USER_PROJECT_ROOT_test"

# Path to the Miniforge/Miniconda installation
CONDA_ROOT="${USER_PROJECT_ROOT}/ppc64le/miniconda"

# Names of your environments
ENV_OPENMM="${USER_PROJECT_ROOT}/ppc64le/envs/ddmd_openmm"
ENV_KERAS="${USER_PROJECT_ROOT}/ppc64le/envs/ddmd_keras"

# Path to the source code (this repository)
SOURCE_DIR="${USER_PROJECT_ROOT}/DeepDriveMD-BEDE/bede_examples"
# =========================================

# DEBUG: Log start time
echo "Wrapper started on $(hostname) at $(date) with args: $@"

# 1. Load System Modules (Bede Specific)
module purge
module load gcc/8.4.0
module load openmpi/4.0.5
module load cuda/11.4.1

# 2. Initialize Conda
source "${CONDA_ROOT}/etc/profile.d/conda.sh"

# 3. Clean Environment Variables
# We unset these to prevent the 'OpenMM' python path from leaking into the 'Keras' environment
unset PYTHONPATH
unset LD_LIBRARY_PATH

# 4. Stage Detection & Environment Activation
if [[ "$@" == *"openmm"* ]] || [[ "$@" == *"aggregation"* ]]; then
    # ==========================================
    # STAGE: MOLECULAR DYNAMICS or AGGREGATION
    # Environment: ddmd_openmm (Python 3.7 + OpenMM + PyTorch)
    # ==========================================
    echo ">> Activating OpenMM Environment..."
    conda activate "$ENV_OPENMM"
    
    export LD_LIBRARY_PATH="${ENV_OPENMM}/lib"
    export PYTHONPATH="${ENV_OPENMM}/lib/python3.7/site-packages"

    # --- INJECTION: MD Parameters ---
    # Only inject if running the simulation stage
    if [[ "$@" == *"openmm"* ]]; then
        for arg in "$@"; do
            if [[ $arg == *.yaml ]]; then
                echo ">> Injecting MD parameters into $arg"
                echo "" >> $arg
                echo "# Injected MD Parameters" >> $arg
                echo "temperature_kelvin: 310.0" >> $arg
                echo "heat_bath_friction_coef: 1.0" >> $arg
                echo "time_step_ps: 0.002" >> $arg
                echo "simulation_length_ns: 0.1" >> $arg
                echo "report_interval_ps: 5.0" >> $arg
                echo "solvent_type: 'implicit'" >> $arg
                # NOTE: Ensure this reference PDB path is correct!
                echo "reference_pdb_file: '${USER_PROJECT_ROOT}/DeepDriveMD-BEDE/bede_examples/data/sys1/comp.pdb'" >> $arg
                echo "fraction_of_contacts: 0.0" >> $arg
            fi
        done
    fi

else
    # ==========================================
    # STAGE: MACHINE LEARNING / SELECTION / AGENT
    # Environment: ddmd_keras (Python 3.6 + TensorFlow + Scikit-Learn)
    # ==========================================
    echo ">> Activating Keras/ML Environment..."
    conda activate "$ENV_KERAS"
    
    export LD_LIBRARY_PATH="${ENV_KERAS}/lib"
    
    # PRIORITY: Load Current Dir ($PWD) first, then Source, then Conda
    # This ensures local patches (like sitecustomize.py if used) take precedence
    export PYTHONPATH="$PWD:${SOURCE_DIR}:${ENV_KERAS}/lib/python3.6/site-packages"

    # --- INJECTION: ML Parameters ---
    for arg in "$@"; do
        if [[ $arg == *.yaml ]]; then
            echo ">> Injecting ML parameters into $arg"
            
            # === PROTEIN SIZE CONFIG ===
            RESIDUES=272    ##example RbsB
            # ===========================

            echo "" >> $arg
            echo "# Injected ML Parameters" >> $arg
            echo "dataset_name: 'contact_map'" >> $arg
            echo "initial_shape: [$RESIDUES, $RESIDUES]" >> $arg
            echo "final_shape: [$RESIDUES, $RESIDUES, 1]" >> $arg
            
            AGG_FILE=$(find . -name "aggregated_data.h5" | head -n 1)
            if [ ! -z "$AGG_FILE" ]; then
                # Get absolute path
                AGG_FILE=$(readlink -f "$AGG_FILE")
                echo "h5_file: '$AGG_FILE'" >> $arg
            fi
            
            echo "last_n_files: 12" >> $arg
            echo "last_n_h5_files: 12" >> $arg
            echo "checkpoint_suffix: '.h5'" >> $arg
        fi
    done

    # Filesystem sync wait (Bede GPFS can be slow)
    if [[ "$@" == *"train"* ]]; then
        sleep 30
    fi
fi

# 5. Execute Task and Log
LOG_FILE="${SOURCE_DIR}/task_error.log"
echo "----------------------------------------------------------------" >> $LOG_FILE
echo "STARTING TASK: $@" >> $LOG_FILE
"$@" >> $LOG_FILE 2>&1

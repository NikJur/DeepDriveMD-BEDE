#!/bin/bash
#SBATCH --account=ACCOUNT_PROJECT_CODE
#SBATCH --job-name=ddmd_test
#SBATCH --time=00:30:00
#SBATCH --partition=gpu
#SBATCH --nodes=1
#SBATCH --gres=gpu:2
#SBATCH --output=ddmd_log_test%j.out
#SBATCH --error=ddmd_log_test%j.err
#SBATCH --mail-type=END
#SBATCH --mail-user=nikolai.juraschko@rfi.ac.uk

# --- Configuration ---
export PROJ_DIR="USER_PROJECT_ROOT"
export INFRA_ENV="$PROJ_DIR/ppc64le/envs/infra_tools"
export MD_ENV="$PROJ_DIR/ppc64le/envs/ddmd_openmm"

# --- 1. Environment & Module Setup ---
echo "--- Loading Modules ---"
module purge
# Using the specific versions found on the system
module load gcc/8.4.0
module load openmpi/4.0.5
module load cuda/11.4.1

# Initialize Conda
source $PROJ_DIR/ppc64le/miniconda/etc/profile.d/conda.sh


# --- 2. Infrastructure Setup (RabbitMQ) ---
echo "--- Starting Infrastructure ---"
conda activate $INFRA_ENV

# 1. CLEANUP: Kill any lingering rabbitmq processes on this node
pkill -u $USER -f beam.smp || true
pkill -u $USER -f epmd || true

# 2. CONFIGURATION: Use a unique local directory for this specific job
# This prevents conflicts with previous runs on different nodes
export RABBITMQ_BASE="/tmp/$USER/rabbitmq_job_$SLURM_JOB_ID"
mkdir -p $RABBITMQ_BASE
export RABBITMQ_MNESIA_BASE="$RABBITMQ_BASE/mnesia"
export RABBITMQ_LOG_BASE="$RABBITMQ_BASE/log"
export RABBITMQ_PID_FILE="$RABBITMQ_BASE/rabbitmq.pid"

echo "RabbitMQ Data Directory: $RABBITMQ_BASE"

# 3. START: Launch Server
rabbitmq-server -detached

# 4. WAIT: Ensure it is actually running
echo "Waiting for RabbitMQ to initialize..."
for i in {1..30}; do
    if rabbitmqctl status > /dev/null 2>&1; then
        echo "RabbitMQ is up and running!"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 2
done

# Final Check
if ! rabbitmqctl status > /dev/null 2>&1; then
    echo "CRITICAL ERROR: RabbitMQ failed to start."
    cat $RABBITMQ_LOG_BASE/*.log
    exit 1
fi

# Export Connection Details
export RMQ_HOSTNAME=localhost
export RMQ_PORT=5672
export RMQ_USERNAME=guest
export RMQ_PASSWORD=guest

echo "RabbitMQ Credentials Set: $RMQ_USERNAME @ $RMQ_HOSTNAME:$RMQ_PORT"

# --- 3. Application Execution ---
echo "--- Starting Application ---"
# Switch to the MD Environment for the orchestrator
conda activate $MD_ENV

# Clean up any previous run data to ensure a fresh start
# WARNING: This deletes the output directory defined in your YAML
RUN_DIR="$PROJ_DIR/DeepDriveMD-BEDE/data"
OUTPUT_DIR="USER_PROJECT_ROOT/DeepDriveMD-BEDE/bede_examples/output_test"
rm -rf $OUTPUT_DIR

echo "Job started at $(date)"
echo "Running on node: $(hostname)"

# Move to the run directory
cd $RUN_DIR

# Launch DeepDriveMD
# Ensure you are using the corrected YAML file (deepdrivemd_test.yaml)
python -m deepdrivemd.deepdrivemd -c deepdrivemd_test.yaml

# --- 4. Cleanup ---
echo "--- Cleanup ---"
# Switch back to infra env to stop RabbitMQ cleanly
conda activate $INFRA_ENV
rabbitmqctl stop

echo "Job finished at $(date)"

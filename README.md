# DeepDriveMD on Bede (IBM PowerPC ppc64le)

This documentation details the setup required to run DeepDriveMD on the **Bede Supercomputer** (IBM PowerAC922, NVIDIA V100, PowerPC `ppc64le`).

We solve the PowerPC dependency conflicts (TensorFlow vs PyTorch) using a **Hybrid Runtime** strategy with two separate compute environments hot-swapped at runtime.

---

## 0. Initial Setup & Cloning

### 📍 Recommended Installation Path
On Bede, it is highly recommended to install the source code in your project's `nobackup` directory to avoid storage quotas and ensure fast I/O performance.

**Navigate to your project directory before cloning (you might need to create your username folder):**
```bash
cd /nobackup/projects/<project_code>/<user_name>/
```

First, create a `sources` directory and clone all required repositories into it.

```bash
mkdir -p sources
cd sources

# 1. Clone this repository
git clone https://github.com/NikJur/DeepDriveMD-BEDE.git

# 2. Clone required dependencies
git clone https://github.com/braceal/molecules.git
git clone https://github.com/braceal/MD-tools.git
```

```bash
#cTO ADD STILL:
mkdir -p ppc64le
cd ppc64le

wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-ppc64le.sh
pwd #(copy result)
bash Miniforge3-Linux-ppc64le.sh
#enter: copied result from pwd/miniconda

source ./miniconda/etc/profile.d/conda.sh
```

## 📂 1. Directory Structure

Ensure your source directory is organised as follows before proceeding:

```text
sources/
├── DeepDriveMD-BEDE/       # This repository
│   ├── bede_env_setup/     # Contains the .yml environment files
│   └── bede_examples/      # Contains example run files
│       ├── data/
│       ├── run_stage.sh
│       ├── deepdrivemd_test.yaml
│       └── deepdrivemd_test.sh
├── molecules/              # Required dependency
└── MD-tools/               # Required dependency
```

## 🐍 2. Environment Setup
We use pre-configured YAML files located in DeepDriveMD-BEDE/bede_env_setup/ to create the three required environments.

Step 1: Create the Environments
Run the following commands from the sources/DeepDriveMD-BEDE directory:

```bash

# 1. Infrastructure (Database & Messaging)
conda env create \
  --prefix ./envs/infra_tools \
  -f ../DeepDriveMD-BEDE/bede_env_setup/environment_infrastructuretools_ppc64le.yml

conda config --prepend channels https://public.dhe.ibm.com/ibmdl/export/pub/software/server/ibm-ai/conda/

# 2. OpenMM (Simulation Stage - Python 3.7)
conda env create \
  --prefix ./envs/ddmd_openmm \
  -f ../DeepDriveMD-BEDE/bede_env_setup/environment_openmm_ppc64le.yml

conda config --set channel_priority flexible

# 3. Keras (ML & Agent Stage - Python 3.6)
conda env create \
  --prefix ./envs/ddmd_keras \
  -f ../DeepDriveMD-BEDE/bede_env_setup/environment_keras_ppc64le.yml

cd ../DeepDriveMD-BEDE
```

Step 2: Install Local Source Code
You must install the local source packages in "editable" mode (-e) for both compute environments.

A. For the OpenMM Environment:
```bash
conda activate /nobackup/projects/<project_code>/<user_name>/sources/ppc64le/envs/ddmd_openmm  #replace <project_code> and <user_name> with your own or adapt path if you installed the environments elsewhere in the previous step

# Install dependencies
cd ../molecules && pip install -e .
cd ../MD-tools && pip install -e .

# Install Main Pipeline
cd ../DeepDriveMD-BEDE && pip install -e .
```

B. For the Keras Environment:
```bash
conda activate /nobackup/projects/<project_code>/<user_name>/sources/ppc64le/envs/ddmd_keras  #replace <project_code> and <user_name> with your own or adapt path if you installed the environments elsewhere

# Install dependencies (Required for data structures)
cd ../molecules && pip install -e .
cd ../MD-tools && pip install -e .

# Install Main Pipeline
cd ../DeepDriveMD-BEDE && pip install -e .
```

## 🛠 3. Code Patches
The following changes have been applied to this branch to support Bede:

1. Fix Agent Inference Engine (deepdrivemd/agents/lof/lof.py)
Switched inference engine from aae (PyTorch) to keras_cvae (TensorFlow) to avoid cross-environment import errors.

Import: Changed deepdrivemd.models.aae.inference to deepdrivemd.models.keras_cvae.inference.

Call: Removed extra arguments (gpu_id, comm) from the generate_embeddings() call.

2. Fix Indexing Crash (deepdrivemd/data/api.py)
Fixed a crash where the Agent selects a global frame index (e.g., 114) that exceeds the local trajectory length (e.g., 20).

Patch: Added modulo arithmetic to write_pdb to wrap the index safely (frame = frame % traj_len).

3. Fix Logging Crash (deepdrivemd/models/keras_cvae/model.py)
Patch: Changed logs["loss"] to logs.get("loss", 0.0) to prevent crashes on missing metrics.


## 🚀 4. Execution
We use a wrapper script to hot-swap environments based on the task type.

The Wrapper Script (bede_examples/run_stage.sh)
This script automatically:

Unsets PYTHONPATH to prevent environment bleeding.

Activates ddmd_openmm for simulation/aggregation.

Activates ddmd_keras for training/agents.

Injects the current source directory into PYTHONPATH.

Running a Job
Modify bede_examples/deepdrivemd_v0_7.sh with your project code.

Submit via SLURM:

```bash
sbatch bede_examples/deepdrivemd_v0_7.sh
```

## 🧪 5. Test Your Installation

We provide a test case in `bede_examples/` to verify that the hybrid environment switching and DeepDriveMD are working correctly.

### Step 1: Configure the Example Scripts
The example files contain a placeholder `USER_PROJECT_ROOT` that needs to be replaced with your actual installation path (e.g., `/nobackup/projects/<project_code>/<user_name>`).

Run these commands to automatically configure the scripts for your user account:

```bash
cd sources/DeepDriveMD-BEDE/

# 1. Get your current project root path (idielly, /nobackup/projects/<project_code>/<user_name>)
# Note: This assumes you are currently inside the 'DeepDriveMD-BEDE' folder
MY_ROOT=$(realpath ../..)

# 2. Inject this path into the Config, Wrapper, and Launcher scripts
sed -i "s|USER_PROJECT_ROOT_test|${MY_ROOT}|g" bede_examples/run_stage.sh
sed -i "s|USER_PROJECT_ROOT|${MY_ROOT}|g" bede_examples/deepdrivemd_test.sh
sed -i "s|USER_PROJECT_ROOT|${MY_ROOT}|g" bede_examples/deepdrivemd_test.yaml

# 3. Verify the change (Optional)
grep "experiment_directory" bede_examples/deepdrivemd_test.yaml
# Should show: /nobackup/projects/<your_project>/<your_user>/...
```

Step 2: Submit the Test Job
Once configured, submit the job to the GPU queue.

```bash
sbatch /bede_examples/deepdrivemd_test.sh
```

Step 3: Monitor Progress
You can track the job's progress using the standard SLURM commands or by tailing the log file.

```bash
# Watch the log (Might take a while to start depending on how busy the cluster is)
tail -f ddmd_run_*.err  # Ctrl + C to exit update
```

If successful, you will see the pipeline transition through:
1. Molecular Dynamics: OpenMM running on GPU.
2. Aggregation: Combining trajectories.
3. Machine Learning: Keras training a CVAE.
4. Agent: Selecting outliers for the next round.

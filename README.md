# DeepDriveMD on Bede (IBM PowerPC ppc64le)

This documentation details the setup required to run DeepDriveMD on the **Bede Supercomputer** (IBM PowerAC922, NVIDIA V100, PowerPC `ppc64le`).

We solve the PowerPC dependency conflicts (TensorFlow vs PyTorch) using a **Hybrid Runtime** strategy with two separate compute environments hot-swapped at runtime.

---

## 0. Initial Setup & Cloning

First, create a `sources` directory and clone all required repositories into it.

```bash
mkdir -p sources
cd sources

# 1. Clone this repository
git clone [https://github.com/NikJur/DeepDriveMD-BEDE.git](https://github.com/NikJur/DeepDriveMD-BEDE.git)

# 2. Clone required dependencies
git clone [https://github.com/braceal/molecules.git](https://github.com/braceal/molecules.git)
git clone [https://github.com/braceal/MD-tools.git](https://github.com/braceal/MD-tools.git)
```

## 📂 1. Directory Structure
Ensure your source directory is organised as follows before proceeding:

```text
sources/
├── DeepDriveMD-BEDE/   # This repository
│   ├── bede_env_setup/     # Contains the .yml environment files
├── molecules/              # Required dependency
└── MD-tools/               # Required dependency
```

## 🐍 2. Environment Setup
We use pre-configured YAML files located in DeepDriveMD-BEDE/bede_env_setup/ to create the three required environments.

Step 1: Create the Environments
Run the following commands from the sources/DeepDriveMD-BEDE directory:

```bash
cd DeepDriveMD-BEDE

# 1. Infrastructure (Database & Messaging)
conda env create -f bede_env_setup/environment_infrastructuretools_ppc64le.yml

# 2. OpenMM (Simulation Stage - Python 3.7)
conda env create -f bede_env_setup/environment_openmm_ppc64le.yml

# 3. Keras (ML & Agent Stage - Python 3.6)
conda env create -f bede_env_setup/environment_keras_ppc64le.yml
```

Step 2: Install Local Source Code
You must install the local source packages in "editable" mode (-e) for both compute environments.

A. For the OpenMM Environment:
```bash
conda activate ddmd_openmm

# Install dependencies
cd ../molecules && pip install -e .
cd ../MD-tools && pip install -e .

# Install Main Pipeline
cd ../DeepDriveMD-BEDE && pip install -e .
```

B. For the Keras Environment:
```bash
conda activate ddmd_keras

# Install dependencies (Required for data structures)
cd ../molecules && pip install -e .
cd ../MD-tools && pip install -e .

# Install Main Pipeline
cd ../DeepDriveMD-BEDE && pip install -e .
```

## 🛠 3. Required Code Patches
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

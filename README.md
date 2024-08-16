# Building Pytorch on NCAR's Derecho supercomputer with a CUDA-Aware Cray-MPICH backend

This repository implements a general process for building recent versions of `pytorch` (~circa 2024) on Derecho from source. 
The purpose is to build a version of `pytorch` to use in *distributed* ML-training workflows making optimal use of the Cray-EX Slingshot 11 (SS11) interconnect.

Distributed-ML in general and SS11 in particular pose some challenges that drive us to build from source rather than choose any of the available Pytorch versions 
from e.g `conda-forge`.  Specifically:
- We want to enable a CUDA-Aware MPI backend using `cray-mpich`.  (Currently for `pytorch` any level of MPI support [requires building from source](https://pytorch.org/tutorials/intermediate/dist_tuto.html#communication-backends).)
- We want to use a SS11-optimized NCCL.  As of this writing, this requires compliling NCCL from source along with using the [AWS OFI NCCL Plugin](https://github.com/aws/aws-ofi-nccl) at specific versions and with specific runtime environment variable settings.
    - **Note that when installing `pytorch` from `conda-forge`, a non-optimal NCCL will generally be installed.** *The application may appear functional but performance will be much degraded for distributed trainig.*
    - Therefore the approach taken here is to install the desired NCCL_plugin, and point `pytorch` to this version at build time to minimize the likelihood of using a non-optimal version. 


## User Installation 
### Quickstart

1. Clone this repo.
   ```bash
   git clone https://github.com/benkirk/derecho-pytorch-mpi.git
   cd derecho-pytorch-mpi
   ```
2. On a Derecho login node:
   ```bash
   export PBS_ACCOUNT=<my_project_ID>

   # build default version of pytorch (currently v2.3.1):
   make build-pytorch-v2.3.1-pbs

   # build pytorch-v2.4.0, aslso supported:
   export PYTORCH_VERSION=v2.4.0
   make build-pytorch-v2.4.0-pbs
   ```
3. Run a sample `pytorch.dist` + MPI backend test on 2 GPU nodes:
   ```bash
   # (from a login node)
   # (1) request an interactive PBS session with 2 GPU nodes:
   qsub -I -l select=2:ncpus=64:mpiprocs=4:ngpus=4 -A ${PBS_ACCOUNT} -q main -l walltime=00:30:00

   # (inside PBS)
   # (2) activate the conda environment:
   module load conda
   conda activate ./env-pytorch-v2.4.0-derecho-gcc-12.2.0-cray-mpich-8.1.27

   # (3) run a minimal torch.dist program with the MPI backend:
   mpiexec -n 8 -ppn 4 --cpu-bind numa ./tests/all_reduce_test.py
   ```

### Customizing the resulting `conda` environment
The process outlined above will create a minimal `conda` environment in the current directory containing the `pytorch` build dependencies and the installed version of `pytorch` itself.  The package list is defined in `config_env.sh` - users may elect to add packages to the embedded `conda.yaml` file, or later through the typical `conda install` command from within the environment. 

## Developer Details

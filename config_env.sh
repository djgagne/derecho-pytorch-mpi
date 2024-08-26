#!/bin/bash

export PYTORCH_VERSION="${PYTORCH_VERSION:-2.3.1}"
export ENV_PYTHON_VERSION="${ENV_PYTHON_VERSION:-3.11}"

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
activate_env=${activate_env:-true}

#-------------------------------------------------------------------------------
# setup host environment
module --force purge
module load ncarenv/23.09 gcc/12.2.0 ncarcompilers cray-mpich/8.1.27 conda/latest cuda/12.2.1
export CONDA_OVERRIDE_CUDA="12.2"

case "${PYTORCH_VERSION}" in
    # see https://github.com/pytorch/vision for torch & vision compatibility
    "2.4.0"*)
        module load cudnn/9.2.0.82-12
        export TORCHVISION_VERSION="0.19.0"
        ;;
    "2.3.1"*)
        module load cudnn/8.8.1.3-12
        export TORCHVISION_VERSION="0.18.1"
        ;;
    "2.2.2"*)
        module load cudnn/8.8.1.3-12
        export TORCHVISION_VERSION="0.17.2"
        ;;
    *)
        echo "ERROR: unknown / unsupported PYTORCH_VERSION: ${PYTORCH_VERSION}"
        exit 1
        ;;
esac
module list

env_name="envs/build-pytorch-${NCAR_BUILD_ENV}"
env_dir="${script_dir}/${env_name}"

echo "PYTORCH_VERSION=${PYTORCH_VERSION}"
echo "TORCHVISION_VERSION=${TORCHVISION_VERSION}"
echo "NCAR_BUILD_ENV=${NCAR_BUILD_ENV}"
echo "env_dir=${env_dir}"

##-------------------------------------------------------------------------------
## clone pytorch source if needed
#make -s -C ${script_dir} pytorch-v${PYTORCH_VERSION}
#make -s -C ${script_dir} vision-v${TORCHVISION_VERSION}

#-------------------------------------------------------------------------------
# function to activate conda env (or, create if needed)
activate_conda_env()
{
    # quick init / return if exists
    if [ -d ${env_dir} ]; then
        conda activate ${env_dir}
        return
    fi

    mkdir -p envs

    # otherwise create a conda env, taking pytorch pip requirements.txt from the
    # pytorch source tree - if we can write to it!
    [ -w ${script_dir} ] || { echo "cannot write to ${script_dir} to create ${env_dir}!!"; exit 1; }

    env_file=${env_dir}.yaml

    cat <<EOF > ${env_file}
channels:
  - conda-forge
  - base
dependencies:
  - python=${ENV_PYTHON_VERSION}
  - astunparse
  - cmake
  - conda-build
  - cusparselt
  - expecttest!=0.2.0
  - ffmpeg>=4.2.2,<5
  - filelock
  - flake8        # <-- torchvision
  - fsspec
  - hypothesis
  - jinja2
  - lark
  - libjpeg-turbo # <-- torchvision
  - libpng        # <-- torchvision
  - lintrunner
  #- mpich=3.4=external_* # <-- MPI is brought in by other pkgs, require mpich/cray-mpich ABI compatibility
  #- mpi4py
  - mkl-include
  - mkl-static
  - pytorch::magma-cuda121 # <-- https://github.com/pytorch/pytorch?tab=readme-ov-file#install-dependencies
  - mypy          # <-- torchvision
  - networkx
  - ninja
  - numpy<2
  - optree>=0.11.0
  - packaging
  - pip
  - psutil
  - pytest        # <-- torchvision
  - pytest-mock   # <-- torchvision
  - pyyaml
  - requests
  - scipy         # <-- torchvision
  - setuptools
  - sympy
  - types-dataclasses
  - typing        # <-- torchvision
  - typing-extensions>=4.8.0
  - pip:
    - build
    - mpi4py
EOF

    cat ${env_file}
    echo "creating ${env_dir}..."
    conda env \
          create \
          -f ${env_file} \
          -p ${env_dir} \
        || exit 1

    mkdir -p ${env_dir}/etc/conda/activate.d ${env_dir}/etc/conda/deactivate.d

    cat <<EOF > ${env_dir}/etc/conda/activate.d/derecho-env_vars.sh
#-------------------------------------------------------------------------------
# defaults for runtime variables we want when operating inside the
# ${env_name} conda environment

# pytorch manage visible devices
unset CUDA_VISIBLE_DEVICES

# Cray-MPICH GPU-Centric bits
#export MPICH_GPU_MANAGED_MEMORY_SUPPORT_ENABLED=1
export MPICH_GPU_SUPPORT_ENABLED=1
export MPICH_OFI_NIC_POLICY=GPU

### Ref: HPE "Running NCCL-Based Applications" v1.1 March 4, 2024
### NCCL with AWS-OFI-Plugin:
# The memory cache monitor is responsible for detecting system memory
# changes made between the virtual addresses used by an application and
# the underlying physical pages. The HPE Slingshot NIC supports
# userfaultfd, memhooks, kdreg2, and disabled. Userfaultfd is a Linux
# kernel feature used to report virtual to physical address mapping
# changes to user space. Memhooks operates by intercepting relevant
# memory allocation and deallocation calls which may result in the
# mappings changing, such as malloc, mmap, free, etc. kdreg2 is a new
# implementation HPE recently delivered. Each has different capabilities
# so some applications may require one monitor but will crash with
# another. The default is currently set to memhooks. HPE has found that
# NCCL will deadlock with memhooks, so this must be set to userfaultfd
# for these applications. HPE has not yet done testing with kdreg2 for
# these applications.
export FI_MR_CACHE_MONITOR=userfaultfd

# This will avoid CUDA allocation calls from the provider that may cause NCCL deadlocks.
export FI_CXI_DISABLE_HOST_REGISTER=1

# This should be set especially for large jobs. It will default to
# 1024. HPE recommends 131072. (Note that any CQ size specified by the
# higher-level application will override the default set with this
# environment variable. HPE does not believe that the OFI Plug-In sets
# this today).
export FI_CXI_DEFAULT_CQ_SIZE=131072

# FI_CXI_DEFAULT_TX_SIZE should be set especially for large jobs that
# are dependent on unexpected rendezvous messaging. The default is 256
# and should be sufficient for most most applications with well- behaved
# communication patterns that do not lead to very large number of
# unexpected messages for specific processes in the job. It should be
# set to at least as large as the number of outstanding unexpected
# rendezvous messages that must be supported for the endpoint plus
# 256. Note that any CQ size specified by the higher-level application
# will override the default set with this environment variable. HPE does
# not believe that the OFI Plug-In sets this today).
unset FI_CXI_DEFAULT_TX_SIZE

# On large systems, this NCCL setting has been found to improve performance.
export NCCL_CROSS_NIC=1

# This NCCL setting is required to enable RDMA between GPUs.
export NCCL_SOCKET_IFNAME=hsn

# NCCL may use any visible interface for bootstrapping communication or
# socket communication. This variable limits NCCL bootstrap/socket usage
# to specific interfaces if desired.
export NCCL_NET_GDR_LEVEL=PHB

# With this setting, if NCCL fails to load the Libfabric plugin at
# runtime, NCCL will terminate.  Without it, NCCL may fallback and run
# on sockets which may be undesirable.
export NCCL_NET="AWS Libfabric"

export NCCL_DEBUG=WARN
#-------------------------------------------------------------------------------
EOF
    # echo "Removing unwanted bits - to reinstall later..."
    # for lib in "libnccl.so*"; do
    #     find ${env_dir} -name ${lib} -print0 | xargs -0 rm -vf
    # done

    cat ${env_dir}/etc/conda/activate.d/derecho-env_vars.sh
    conda activate ${env_dir}

    # fix the conda shebang so conda build works!!
    # https://conda.discourse.group/t/conda-build-modulenotfounderror-no-module-named-conda/538/2
    sed -i "s,\#\!/usr/bin/env python,#\!${CONDA_PREFIX}/bin/python," ${CONDA_PREFIX}/*bin/conda

    return
}

# save these **before** intializaing the monster conda environment
# defined above, that will bring in its own MPI we want no part of...
save_MPICC=$(which mpicc)
save_MPICXX=$(which mpicxx)

[[ true == ${activate_env} ]] && activate_conda_env

#-------------------------------------------------------------------------------
echo "#--> setting buildtime variables we want when compiling pytorch / torchvision"
#set -x
export MPICC=${save_MPICC}
export MPICXX=${save_MPICXX}
export CC=${MPICC}
export CXX=${MPICXX}
export CMAKE_C_COMPILER=${CC}
export CMAKE_CXX_COMPILER=${CXX}
export CFLAGS='-Wno-maybe-uninitialized -Wno-uninitialized -Wno-nonnull'
export CXXFLAGS="${CFLAGS}"

export CMAKE_PREFIX_PATH=${CONDA_PREFIX}

export MAX_JOBS="${MAX_JOBS:-96}"

# pytorch:
export BUILD_TEST=0
export USE_FFMPEG=1
export USE_BLAS=MKL
#export MKL_ROOT=/notfound
#export MKL_LIB_DIR=/notfound
#export MKL_INCLUDE_DIR=/notfound
export USE_MPI=1
export USE_CUDA=1
export TORCH_CUDA_ARCH_LIST="8.0" # <-- A100s
export USE_CUDNN=1
export CUDNN_LIBRARY=${NCAR_ROOT_CUDNN}
export CUDNN_LIB_DIR=${NCAR_ROOT_CUDNN}/lib
export CUDNN_INCLUDE_DIR=${NCAR_ROOT_CUDNN}/include
export USE_CUSPARSELT=1
export USE_SYSTEM_NCCL=1
export NCCL_ROOT=${script_dir}/nccl-ofi/install
export NCCL_LIB_DIR=${NCCL_ROOT}/lib
export NCCL_INCLUDE_DIR=${NCCL_ROOT}/include
export PYTORCH_BUILD_VERSION="${PYTORCH_VERSION}+${NCAR_BUILD_ENV}"
export PYTORCH_BUILD_NUMBER=1

# torchvision:
export FORCE_CUDA=1 # <-- https://github.com/pytorch/vision/blob/main/CONTRIBUTING.md#clone-and-install-torchvision
export TORCHVISION_USE_FFMPEG=1
export TORCHVISION_BUILD_VERSION="${TORCHVISION_VERSION}+${NCAR_BUILD_ENV_COMPILER}"
set +x
#-------------------------------------------------------------------------------

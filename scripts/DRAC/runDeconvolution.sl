#!/bin/bash
#SBATCH --job-name=Deconvolution
#SBATCH --account=PROJECTACCOUNT
#SBATCH --time=RUNTIME
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=NUMCPUS
#SBATCH --mem=RAM
#SBATCH --mail-user=MYEMAIL
#SBATCH --mail-type=MAILTYPE
#SBATCH --output=OUTPUTDIR
#SBATCH --error=ERRORDIR

module load StdEnv/2023
module load matlab/2026a.3

matlab -nodisplay -batch "addpath(genpath('SCRIPTPATH')); runDeconvolution"
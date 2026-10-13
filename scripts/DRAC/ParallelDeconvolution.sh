#!/bin/bash

########################################################################################

### Enter your 3-letter initials below; this is used to name jobs based on Animal ID
### For example, the animal "ZHA001" has initials "ZHA" and IDlength=6 characters
### For example, the animal "A12" has initials "A" and IDlength=3
### For example, the animal "JKA-HPC-09" has initials "JKA" and IDlength=10
### If your animals don't have a consistent naming scheme (e.g., just random numbers like 124 or 2592) 
### then your jobs will still run but the
### email you get naming your job will just look a bit odd. This step is simply to make jobs readable when submitting.

### Note that this and the email input are both OPTIONAL! If you put nothing, or put something incorrect, 
### the script will likely still launch your jobs. Except that the job names might look strange and 
### you won't get e-mail notifications

initials="JKA"
IDlength=10
target_dir="Miniscope*" # Searching for all directories with this name in root directory to run the script

script_path="/lustre10/scratch/abadchi/CA1_project/linear_track/RUN/runDeconvolution.m" # where you store your .m MATLAB files
slurm_path="/lustre10/scratch/abadchi/CA1_project/linear_track/RUN/runDeconvolution.sl"  # where you store your .sl SLURM files

### Enter the full parent directory for analysis to run in the () brackets (default and recommended is pwd)
pwd=$(pwd)

largeRAM=51200 # memory limit for each job (Default: 220000)

largeruntime="1:00:00" # time limit for each job

largeCPU=8 # number of cpus for each job (Default: 4)

# SETUP SLURM HERE #
project_account="rrg-markpb68" # project allocation to use
email="mjka88@gmail.com" # email to send notifications to
mailtype="ALL" # type of email notifications you want; END, FAIL, ALL, BEGIN, etc.
output_directory="/lustre10/scratch/abadchi/SLURMS/deconvolution" # directory where you want the output and errors of slurm files to be saved
output_subs=1
# note that for multidparamloop we will create subdirectories based on animal ID
# if you instead want to save all the outputs in the same directory, set output_subs=0

# output directory will be created if it doesn't exist
if [ ! -d "$output_directory" ]; then
  mkdir -p $output_directory
fi

##############################################################################################

data=$(find $pwd -type d -name "$target_dir")

for session in $data
do
	cd $session
	if [ ! -f "ms_union.mat" ]; then
		echo "no ms file was found!"
	elif [ ! -f "deconv_union.mat" ]; then
		runtime=$largeruntime
		RAM=$largeRAM
		CPUS=$largeCPU

		echo "Analyzing $session"
		cp $slurm_path .

		# create animalID-date as taskname
		ID=$initials${session#*$initials}
		ID=${ID::$IDlength}

		if [ $output_subs == 1 ]; then
			#output_directory="${output_directory}/${ID}"
			output_directory1="${output_directory}/${ID}"
			if [ ! -d "$output_directory1" ]; then
				mkdir -p $output_directory1
			fi
		fi

		date=202${session#*202}; date=${date::10}
		ID="$ID-$date"

		# replace placeholders in SLURM script
		slurm_name="${slurm_path##*/}"
		script_path_only="${script_path%/*}"
		sed -i -e "s|SCRIPTPATH|${script_path_only}|g" $slurm_name
		sed -i -e "s/TASKNAME/$ID/g" $slurm_name
		sed -i -e "s/MYEMAIL/$email/g" $slurm_name
		sed -i -e "s/PROJECTACCOUNT/$project_account/g" $slurm_name
		sed -i -e "s/MAILTYPE/$mailtype/g" $slurm_name
		sed -i -e "s|OUTPUTDIR|${output_directory1}/${date}_%j.out|g" $slurm_name
		sed -i -e "s|ERRORDIR|${output_directory1}/errors/${date}_%j.err|g" $slurm_name
		sed -i -e "s|RAM|${RAM}|g" $slurm_name
		sed -i -e "s|RUNTIME|${runtime}|g" $slurm_name
		sed -i -e "s|NUMCPUS|${CPUS}|g" $slurm_name
		sbatch $slurm_name
		sleep 1
	fi
done

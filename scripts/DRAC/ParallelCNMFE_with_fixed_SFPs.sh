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

# where you store your .m MATLAB files
script_path="/lustre10/scratch/abadchi/CA1_project/linear_track/RUN/runCNMFe_with_fixed_SFPs.m"
# where you store your .sl SLURM files 
slurm_path="/lustre10/scratch/abadchi/CA1_project/linear_track/RUN/runCNMFe_with_fixed_SFPs.sl"  

### Enter the full parent directory for analysis to run in the () brackets (default and recommended is pwd)
# Store the current working directory; this is the parent directory searched
# for session directories matching the target_dir pattern below.
pwd=$(pwd)

RAM_amount=76800 # MB, memory limit for RUN
#RAM_amount=512000 # MB, memory limit for PRE

runtime_amount="01:00:00" # time limit for each job; RUN
#runtime_amount="03:30:00" # time limit for each job; PRE

CPU_amount=8 # number of cpus for each job

# SETUP SLURM HERE #
project_account="rrg-markpb68" # project allocation to use
email="mjka88@gmail.com" # email to send notifications to
mailtype="ALL" # type of email notifications you want; END, FAIL, ALL, BEGIN, etc.

# directory where you want the output and errors of slurm files to be saved
output_directory="/lustre10/scratch/abadchi/SLURMS/CNMFe" 

output_subs=1
# note that for multidparamloop we will create subdirectories based on animal ID
# if you instead want to save all the outputs in the same directory, set output_subs=0

# output directory will be created if it doesn't exist
if [ ! -d "$output_directory" ]; then
	mkdir -p $output_directory
fi

###############################  OTHER PARAMS  ##############################################

minimum_size=100M # minimum video file size; default is 1M (1 megabyte)
minimum_number=1 # min number of avi files to trigger analysis; set this to 1 if you've already concatenated your videos

##############################################################################################


# Find all directories matching the target pattern under the current working directory.
# This builds the list of sessions to iterate over for CNMFe processing.
data=$(find $pwd -type d -name "$target_dir")

for session in $data
do
	cd $session
	numVideos=$(find . -type f -name "*.avi" | wc -l)  # Count .avi files in the current session directory and subdirectories
	filepart_check=$(find . -type f -name "*filepart*" | wc -l)
	video_sizes_check=$(find . -type f -size +$minimum_size -name "*.avi" | wc -l)

	# Get the size of msvideo.avi in bytes. The command substitution stores only
	# the numeric size (the first field of du's output) in zero_size for the
	# empty-file check below.
	# zero_size=$(du -b "msvideo.avi" | cut -f1)

	if (( $filepart_check > 0 )); then
        echo "ERROR: Incomplete uploading in $session"
	elif [ -f "runCNMFe_with_fixed_SFPs.sl" ]; then
	# elif [ -f "ms_union.mat" ]; then
		echo "DONE $session it is already analyzed/analyzing"
	elif [ -f "CNMFE-running.temp" ]; then # script used to make this but no longer does I think
		echo "SKIPPED $session already running"
	elif (( $numVideos < $minimum_number )); then
		echo "SKIPPED: too few video files to analyze $session"
	elif (( $numVideos != $video_sizes_check )); then
		echo "ERROR: Some video files may be too small or corrupt in $session"
	elif find . -type f -name "SFP_union.mat" -print -quit | grep -q . && find . -type f -name "msvideo.avi" -print -quit | grep -q .; then
		# if (( $zero_size == 0 )); then
		# 	echo "ERROR: msvideo.avi is empty in $session"
		# 	continue
		# fi
		
		runtime=$runtime_amount
		RAM=$RAM_amount
		CPUS=$CPU_amount

		echo "Analyzing $session"
		
		# Copy the SLURM job template into the current session directory.
		# The copied file is customized below with session-specific settings.
		cp $slurm_path .

		# create animalID-date as taskname
		# Build the animal ID by keeping the text from the configured initials onward.
		ID=$initials${session#*$initials}
		# Limit the extracted ID to the expected number of characters.
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

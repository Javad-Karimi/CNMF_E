#!/usr/bin/env bash

# This script deletes files with the given exact names from the specified root directory and all its subdirectories. It supports a dry run mode to preview the files that would be deleted without actually removing them.
# USAGE: bash scripts/DRAC/delete_files.sh ROOT_DIRECTORY FILE_NAME [FILE_NAME ...]  
# EXAMPLE: bash /home/abadchi/links/CNMF_E/scripts/DRAC/delete_files.sh -n ...
# /lustre10/scratch/abadchi/CA1_project/linear_track/RUN/JKA-HPC-09/ ...
# runCNMFe_with_fixed_SFPs.sl ms_union.mat .dir.mat
# "-n" is optional and will print the matching files without deleting them.
# remove the "-n" option to actually delete the files.

set -euo pipefail

usage() {
    printf 'Usage: %s [-n] ROOT_DIRECTORY FILE_NAME [FILE_NAME ...]\n' "$0"
    printf '\nDelete files with the given exact names from ROOT_DIRECTORY and all subdirectories.\n'
    printf '  -n  Dry run: print matching files without deleting them.\n'
    printf '\nExample:\n'
    printf '  %s /path/to/data results.mat temporary.log\n' "$0"
}

dry_run=false
if [[ "${1:-}" == "-n" ]]; then
    dry_run=true
    shift
fi

if (( $# < 2 )); then
    usage >&2
    exit 1
fi

root_directory=$1
shift

if [[ ! -d "$root_directory" ]]; then
    printf 'Error: directory does not exist: %s\n' "$root_directory" >&2
    exit 1
fi

for file_name in "$@"; do
    if [[ -z "$file_name" || "$file_name" == */* ]]; then
        printf 'Error: file names must be non-empty names without path separators: %s\n' "$file_name" >&2
        exit 1
    fi

    if [[ "$dry_run" == true ]]; then
        find "$root_directory" -type f -name "$file_name" -print
    else
        find "$root_directory" -type f -name "$file_name" -print -delete
    fi
done
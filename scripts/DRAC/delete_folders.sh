#!/usr/bin/env bash

# This script deletes folders with the given exact names from the specified root directory and all its subdirectories. It supports a dry run mode to preview the folders that would be deleted without actually removing them.
# USAGE: bash scripts/DRAC/delete_folders.sh ROOT_DIRECTORY FOLDER_NAME [FOLDER_NAME ...]
# EXAMPLE: bash scripts/DRAC/delete_folders.sh /path/to/data cache output
# Example: bash /home/abadchi/links/CNMF_E/scripts/DRAC/delete_folders.sh -n 
# /lustre10/scratch/abadchi/CA1_project/linear_track/RUN/JKA-HPC-09/ 'frames_*'
# "-n" is optional and will print the matching folders without deleting them.
# remove the "-n" option to actually delete the folders.

set -euo pipefail

usage() {
    printf 'Usage: %s [-n] ROOT_DIRECTORY FOLDER_NAME [FOLDER_NAME ...]\n' "$0"
    printf '\nDelete folders with the given exact names from ROOT_DIRECTORY and all subdirectories.\n'
    printf '  -n  Dry run: print matching folders without deleting them.\n'
    printf '\nExample:\n'
    printf '  %s /path/to/data cache output\n' "$0"
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

for folder_name in "$@"; do
    if [[ -z "$folder_name" || "$folder_name" == */* ]]; then
        printf 'Error: folder names must be non-empty names without path separators: %s\n' "$folder_name" >&2
        exit 1
    fi

    if [[ "$dry_run" == true ]]; then
        find "$root_directory" -mindepth 1 -type d -name "$folder_name" -print -prune
    else
        find "$root_directory" -mindepth 1 -type d -name "$folder_name" -print -prune -exec rm -rf -- {} +
    fi
done

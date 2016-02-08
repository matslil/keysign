#!/bin/bash -eu

# Copyright (C) Mats G. Liljegren <mats@mexit.se>
# SPDX-License-Identifier: BSD-2-Clause

# Download keys found in key list file, and verify their fingerprints.
# Will also copy sign.sh script and the key list file to the output
# directory to make it ready to be exported to an air-gap computer.
#
# Syntax:
#   dl-keys.sh <key list file> [<key server>]
#
# <key server> defaults to pool.sks-keyservers.net.

# Parameters
readonly listfile="$1"
readonly keyserver="${2:-pool.sks-keyservers.net}"

# Working directory
readonly wdir=$(mktemp -d -t dl-keys.XXXXXXXXXX)

# Output directory
readonly odir="$(pwd)/out"

# Cleanup function run when script exits
function finish {
    rm -rf "$wdir"
}
  
trap finish EXIT
    
# Download key to a new and unique keyring file, verify fingerprint
download() {
    # Command parameters
    declare -r keyid="$1"
    declare -r fpr="$2"

    # Name of keyring file
    declare -r keyring="${wdir}/${keyid}.keyring"

    # Name of file containing key, this is the final result of this function
    declare -r keyfile="${odir}/${keyid}.gpg"

    # Download key and store output so the fingerprint can be parsed
    downloadOutput=$(gpg2 --status-fd 1 --no-default-keyring --keyring ${keyring} --keyserver $keyserver --recv-keys ${keyid} 2>/dev/null) || {
	printf "WARNING: Key $keyid: Could not download: ${downloadOutput}\n"
	rm ${keyring}
	return 1
    }

    # Parse the output to check the fingerprint
    printf -- "$downloadOutput" | fgrep -- '[GNUPG:] IMPORT_OK 1 '"$fpr" || {
	rm ${keyring}
	printf "WARNING: Key $keyid: Fingerprint mismatch: ${downloadOutput}\n" >&2
	return 1
    }

    # Create key file
    if ! gpg2 --no-default-keyring --keyring ${keyring} --output ${keyfile} --export ${keyid}; then
	printf "WARNING: Key $keyid: Failed to export key\n" >&2
	rm ${keyring}*
	return 1
    fi

    rm ${keyring}*
    
    return 0
}

#
# Main function
#

printf "Key list file: ${listfile}\n\n"
printf "Keyserver....: ${keyserver}\n"

# Create output directory if needed
mkdir -p ${odir}

# Warn of output directory already existed with contents
[ -e ${odir} ] && {
    read -p "WARNING: Output directory not empty, press 'y' to continue anyway: " -n 1 answer
    printf "\n"
    [[ $answer != 'y' ]] && {
	printf "ABORTING\n"
	exit 1
    }
}

# Parse key list file
# Example of entry:
# pub   rsa4096/90294812 2009-07-18
#       Key fingerprint = F1ED 345E 12A7 56A8 189D  35F3 763A 6811 1269 1706
# uid  Bill Example (Example UID) <bill.example@email.net>

while true; do
    read line
    [[ $line =~ ^pub ]] || continue
    
    keyid=$(echo "$line" | sed -r 's%^.*/([0-9A-F]*) .*%\1%')
    read line
    fpr=$(echo "$line" | sed -r 's/.*= *(.*)/\1/' | tr -d ' ')

    if download "$keyid" "$fpr"; then
        printf "$keyid: Sucessfully downloaded\n"
    else
        printf "WARNING: $keyid: Failed, skipping!\n" >&2
    fi
done <$listfile

# copy key list file to output directory
cp $listfile $odir

# Copy sign.sh script that is expected to reside in the same directory as
# this script. It is copied to output directory.
cp "$(dirname "$(readlink -f "$BASH_SOURCE")")/sign.sh" $odir


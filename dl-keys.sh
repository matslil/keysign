#!/bin/bash -eu

#readonly keyserver="ksp.fosdem.org"
readonly keyserver="$1"
readonly listfile="$2"

readonly wdir=$(mktemp -d -t dl-keys.XXXXXXXXXX)
readonly odir="$(pwd)/out"

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

    downloadOutput=$(gpg2 --status-fd 1 --no-default-keyring --keyring ${keyring} --keyserver $keyserver --recv-keys ${keyid} 2>/dev/null) || {
	printf "WARNING: Key $keyid: Could not download: ${downloadOutput}\n"
	rm ${keyring}
	return 1
    }

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

printf "Keyserver....: $1\n"
printf "Key list file: $2\n\n"

[ -e * ] && {
    read -p "WARNING: Current directory not empty, press 'y' to continue anyway: " -n 1 answer
    printf "\n"
    [[ $answer != 'y' ]] && {
	printf "ABORTING\n"
	exit 1
    }
}

# Export key to be signed including signature for given uid.
# Key will be exported to a file encrypted by the key to be signed.
#
# Assumptions:
#   The key is found in ${keyid}.gpg, which should be done by
#   downloadAndSignKey()

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

cp $listfile $odir
cp "$(dirname "$(readlink -f "$BASH_SOURCE")")/sign.sh" $odir


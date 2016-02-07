#!/bin/bash -eu


#################################
# Configurations


# Change this to your own policy!
readonly policyUrl="http://mats.mexit.se/files/gpg-signature-policy.md"
readonly signingKeyId=CB9C8689AEA6A954

# Be verbose, 0 = false, 1 = true
readonly verbose=0


#################################
# End of configurations

# Determine gpg verbose parameter
case $verbose in
    0) VERB="-q" ;;
    1) VERB="" ;;
    2) VERB="-v" ;;
    *) VERB="-vv" ;;
esac

# Working directory, cleaned up at exit
readonly wdir=$(mktemp -d -t sign.XXXXXXXXXX)

# Output directory, this is where all resulting files are placed
readonly odir="$(pwd)/out"

# GPG command with ubiquitous parameters
readonly GPG="$(which gpg2)"

# Make sure GPG uses the correct TTY
export GPG_TTY=$(tty)

# Function run when exiting script
function finish {
    rm -rf "$wdir"
}

# Make sure above function is run when script exits
trap finish EXIT
  
# Import key file, sign the key, and export to a keyfile in the working
# directory

# Export key to be signed including signature for given uid.
# Key will be exported to a file encrypted by the key to be signed.
#
# Assumptions:
#   The key is found in ${wdir}/${keyid}.gpg, which should be done by signKey()

createSignature() {
    declare -r keyid="$1"
    declare -r uid="$2"
    declare -r uidIdx="$3"
    declare -r keyfile="$4"

    # E-mail part of uid
    declare -r email=$(echo "$uid" | sed -r 's/.*<(.*)>.*/\1/')

    # Keyring to use while working with the key
    declare -r keyring="${wdir}/${keyid}.${uidIdx}.keyring"
    
    # If no email, then nothing to do
    [[ -z $email ]] && return 0

    $GPG $VERB --yes --no-default-keyring --keyring ${keyring} --import ${keyfile}

    declare -r fullKeyId=$($GPG $VERB --yes --no-default-keyring --keyring ${keyring}  --with-colons --list-keys ${keyid} | egrep '^pub:' -m 1 | sed -r 's/^.*:(.*?):.*:.*:.*:.*:.*:.*:.*:$/\1/')

    declare -a uids

    # Get list of all uids in the key
    IFS='
' uids=($($GPG $VERB --yes --no-default-keyring --keyring ${keyring} --with-colons --list-keys ${keyid} | sed -rn 's/^uid:.*:(.*):$/\1/p'))

    # Filter out unwanted uids
    declare -ia removeUids=()
    declare -i idx
    for (( idx = 0; idx < ${#uids[@]}; idx++ )); do
	if [[ ${uids[idx]} != $uid ]]; then
	    # Unwanted uid, mark for removal
	    removeUids+=($(( idx+1 )) )
	fi
    done

    [[ ${#removeUids[@]} > 0 ]] && $GPG $VERB --yes --no-default-keyring --keyring ${keyring} --key-edit ${keyid} ${removeUids[@]:-} deluid save

    # File name of key to create
    declare -r keyfileToCreate="${odir}/${fullKeyId}.${uidIdx}-signed-by-${signingKeyId}.asc"
    
    # Export key now containing only the wanted uid
    $GPG $VERB --yes --no-default-keyring --keyring ${keyring} --output ${keyfileToCreate} --armor --export ${keyid}

    printf "\n---- ${keyfileToCreate}: Created ----\n\n"
}

signKey() {
    declare -r keyid="$1"

    declare -r keyfile="${wdir}/${keyid}.gpg"

    # Import key from file to working keyring    
    $GPG $VERB --yes --import ${keyid}.gpg

    # Remove others signatures
    $GPG $VERB --yes --edit-key ${keyid} clean minimize save

    # Add our own signature
    $GPG $VERB --yes --sig-policy-url ${policyUrl}  --default-key ${signingKeyId} --sign-key ${keyid}

    # Export to a new key file from keyring
    $GPG $VERB --yes --output ${keyfile} --export ${keyid}

    declare -a uids

    # Get list of all uids in the key
    IFS='
' uids=($($GPG $VERB --yes --with-colons --list-keys ${keyid} | sed -rn 's/^uid:[-mfuws]:.*:(.*):$/\1/p'))

    declare -i idx
    for (( idx = 0; idx < ${#uids[@]}; idx++ )); do
	createSignature "${keyid}" "${uids[idx]}" "$(( idx+1 ))" "${keyfile}"
    done
}

#
# Main function
#

# Check that the policy URL is correct
read -p "$policyUrl: Enter 'y' if this is the correct policy URL: " -n 1 answer
echo
[[ $answer != y ]] && {
   printf "ABORTING\n"
   exit 1
}

# Copy GNUPG configuration, so we do not alter the original one
mkdir ${wdir}/gnupg
cp -r ${GNUPGHOME:-~/.gnupg}/* ${wdir}/gnupg

# Start using our own GNUPG configuration
export GNUPGHOME=${wdir}/gnupg

# Ensure correct access rights to gnupg directory
chmod 0700 $GNUPGHOME

# Create output directory, if needed
mkdir -p ${odir}

# Iterate all GPG files in current directory
for file in *.gpg; do
    keyid=$(basename $file .gpg)
    signKey "$keyid" || printf "**** WARNING: Key ${keyid} not signed!\n" >&2
done


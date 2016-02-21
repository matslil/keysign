#!/bin/bash -eu

# Copyright (C) Mats G. Liljegren <mats@mexit.se>
# SPDX-License-Identifier: BSD-2-Clause

# Iterate all files created by sign.sh, and send them to the respective
# user ID.
#
# To use this script, first create the following file:
#     ~/gpg-signing/smtp-passwd.cfg
# Use file smtp-passwd.cfg.example as a starting point.
#
# If you want to do a dry test run, change the value for variable "dryRun"
# to "1".
#
# Make sure your current working directory is where the files are, and
# invoke this script without any parameters.
#
# Prerequisites:
# - gpg2 (you can probably change to gpg if you prefer that)
# - mime-construct
# - sendemail 

dryRun=0

# Read configuration file
source ~/.gpg-signing/smtp-passwd.cfg

# Working directory
readonly wdir=$(mktemp -d -t send-email.XXXXXXXXXX)

# Output directory
readonly odir="$(pwd)/out"

# Cleanup function run when script exits
function finish {
    rm -rf "$wdir"
}
      
trap finish EXIT

#
# Check for needed dependencies
#

readonly GPG="$(which gpg2)"

[[ -z "${GPG:-}" ]] && {
    printf -- "Could not find 'gpg2' in PATH, please install it.\n"
    exit 1
}

readonly MIME_CONSTRUCT="$(which mime-construct)"

[[ -z "${MIME_CONSTRUCT:-}" ]] && {
    printf -- "Could not find 'mime-construct' in PATH, please install it.\n"
    exit 1
}

readonly SENDEMAIL="$(which sendemail)"

[[ -z "${SENDEMAIL:-}" ]] && {
    printf -- "Could not find 'sendemail' in PATH, please install it.\n"
    exit 1
}

#
# Print send-mail.template to stdout while replacing keywords with parameters
# given
#
# Globals:
#   signerName - Defined by configuration file
#

translateTemplate() {
    declare -r keyId="$1"
    declare -r signeeUid="$2"

    declare -r msgTemplate="$(dirname "$(readlink -f "$BASH_SOURCE")")/send-email.template"

    cat $msgTemplate | sed 's/\${keyId}/'"${keyId}/g" | sed 's/\${signerName}/'"${signerName}/g" | sed 's/\${signeeUid}/'"${signeeUid}/g"
}

#
# Create and send the mail
#

createMail() {
    declare -r signeeUid="$1"
    declare -r keyFile="$2"
    declare -r keyId="$3"

    # Extract destination email address from signee uid
    declare -r signeeEmail=$(echo "${signeeUid}" | sed -rn 's/.*<(.*)>/\1/p')

    [[ -z "${signeeEmail:-}" ]] && {
        printf -- "$signeeEmail: No e-mail address to send to, skipping\n"
	return 0
    }

    declare -r nl='
'    
    declare -r enc_type=application/pgp-encrypted
    declare -r enc_params="Version: 1$nl"

    # Create e-mail in layers, starting from the most inner part which consists
    # message and the key to be sent, all packaged as a stand-alone mime text
    declare -r mailBodyToEncrypt=$($MIME_CONSTRUCT --output --type 'text/plain; charset="utf-8"' --file <(translateTemplate "${keyId}" "${signeeUid}") --type "application/pgp-keys" --attachment "$keyFile" --file $keyFile) 

    [[ -z "${mailBodyToEncrypt:-}" ]] && return 1 

    # Import key to our own keyring so we can use it for encryption
    # It might be imported already if we're sending several messages for the same public key,
    # so ignore errors.
    $GPG --no-default-keyring --keyring ${wdir}/${keyId}.keyring --import ${keyFile} || true

    # Encrypt the inner e-mail text with the public key
    declare -r mailBodyEncrypted=$(echo "$mailBodyToEncrypt" | $GPG --no-default-keyring --keyring ${wdir}/${keyId}.keyring --trust-model always --encrypt --armor -r "$signeeEmail") 

    [[ -z "${mailBodyEncrypted:-}" ]] && return 1

    # Create an outer mime envelope for the actual message, consisting of
    # non-encrypted headers and an encrypted body
    declare -r mailBody=$(echo "$mailBodyEncrypted" | $MIME_CONSTRUCT --output \
          --subject "Your signed PGP key $keyId" \
	  --to "$signeeEmail" \
          --multipart "multipart/encrypted; protocol=\"$enc_type\"" \
          --type "$enc_type" \
	  --attachment "signedkey.msg" \
	  --encoding '7bit' \
	  --string "$enc_params" \
	  --attachment "msg.asc" \
	  --type 'application/octet-stream; name="msg.asc"' \
	  --part-header "Content-Disposition: inline; filename=\"msg.asc\"" \
	  --file -) 

    # Send e-mail unless dyRun is true
    (( dryRun )) || echo "$mailBody" | $SENDEMAIL -q -l sendemail.log -o message-format=raw -s "$smtpServer" -t "$signeeEmail" -f "${smtpFrom}" -o username="$smtpUser" -o password="$smtpPasswd" -o tls="$smtpTls" || return 1

    printf -- "${signeeUid} ${keyId}: Mail sent to $signeeEmail"
    (( dryRun )) && printf -- " - Dry run"
    echo
}

#
# Iterate key files found in the current directory and send mail for each of them
#

iterateFiles() {
    declare signeeKeyId
    declare signeeUid
    declare signerKeyId
    declare file
 
    for file in *-signed-by-${signerFullKeyId}.asc; do
	printf -- "--- File: ${file}\n"

        # First part of file name is the key ID of signee key, extract it
	read signeeKeyId signerKeyId < <(echo "$file" | sed -r 's/^([0-9A-Za-z]*)\.[0-9]+-signed-by-([0-9A-Za-z]*).asc$/\1 \2/')

	# Get signee UID from the key file
	signeeUid="$($GPG --list-packets $file | egrep -m1 '^:user ID packet: ' | sed -rn 's/^:user ID packet: \"(.*)\"/\1/p')"

	# Send the e-mail
        createMail "${signeeUid}" "${file}" "${signeeKeyId}" || printf -- "WARNING: ${signeeUid} ${signeeKeyId}: Failed sending mail, ignoring\n"
    done
}

iterateFiles

printf -- "\n---- Done ----\n\n"


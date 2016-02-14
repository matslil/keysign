#!/bin/bash -eux

# Copyright (C) Mats G. Liljegren <mats@mexit.se>
# SPDX-License-Identifier: BSD-2-Clause

dryRun=1

# Read configuration file
source ~/.gpg-signing/smtp-passwd.cfg

readonly GPG="$(which gpg2)"

[[ -z "$GPG" ]] && {
    printf "Could not find 'gpg2' in PATH, please install it."
    exit 1
}

readonly MIME_CONSTRUCT="$(which mime-construct)"

[[ -z "$MIME_CONSTRUCT" ]] && {
    printf "Could not find 'mime-construct' in PATH, please install it."
    exit 1
}

readonly SENDEMAIL="$(which sendemail)"

[[ -z "$SENDEMAIL" ]] && {
    printf "Could not find 'sendemail' in PATH, please install it."
    exit 1
}

translateTemplate() {
    declare -r keyId="$1"
    declare -r signerName="$2"

    declare -r msgTemplate="$(dirname "$(readlink -f "$BASH_SOURCE")")/send-email.template"

    cat $msgTemplate | sed 's/\${keyId}/'"${keyId}/" | sed 's/\${signerName}/'"${signerName}/"
}

createMail() {
    declare -r signeeEmail="$1"
    declare -r keyFile="$2"
    declare -r keyId="$3"

    declare -r nl='
'    
    declare -r enc_type=application/pgp-encrypted
    declare -r enc_params="Version: 1$nl"

    declare -r mailBodyToEncrypt=$($MIME_CONSTRUCT --subpart --file <(translateTemplate "${keyId}" "${signerName}") --file-attach $keyFile)

    declare -r mailBodyEncrypted=$(echo "$mailBodyToEncrypt" | $GPG --encrypt --armor -r "$signeeEmail")

    declare -r mailBody=$(echo "$mailBodyEncrypted" | $MIME_CONSTRUCT --output \
          --subject "Your signed PGP key $keyId" \
	  --to "$signeeEmail" \
          --multipart "multipart/encrypted; protocol=\"$enc_type\"" \
          --type "$enc_type" \
	  --string "$enc_params" \
	  --file -)

    (( dryRun )) || echo "$mailBody" | $SENDEMAIL -q -l sendemail.log -o message-format=raw -s "$smtpServer" -t "$signeeEmail" -f "${smtpFrom}" -o username="$smtpUser" -o password="$smtpPasswd" -o tls="$smtpTls"

    printf "${signeeEmail} ${keyId}: Mail sent to $signeeEmail"
    (( dryRun )) && printf " - Dry run"
    echo
}

iterateFiles() {
    declare signeeKeyId
    declare signeeEmail
    declare signerKeyId
 
    for file in *-signed-by-${signerFullKeyId}.asc; do
	read signeeKeyId signerKeyId < <(echo "$file" | sed -r 's/^([0-9A-Za-z]*)\.[0-9]+-signed-by-([0-9A-Za-z]*).asc$/\1 \2/')
	signeeEmail="$($GPG --list-packets $file | egrep -m1 '^:user ID packet: ' | sed -rn 's/.*<(.*)>\"/\1/p')"
    done
}

createMail mats@mexit.se 2209D6902F969C95.1-signed-by-CB9C8689AEA6A954.asc CB9C8689AEA6A954 CB9C8689AEA6A954

#iterateFiles


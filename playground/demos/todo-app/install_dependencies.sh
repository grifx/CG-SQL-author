#!/bin/bash

set -o errexit -o nounset -o pipefail

while read -r dest_file url checksum; do
    echo "Installing $dest_file $url $checksum"
    mkdir -p "$(dirname "$dest_file")"
    curl -s -o "$dest_file" "$url"

    read calculated_checksum _ < <(sha1sum "$dest_file")

    if [[ "$calculated_checksum" != "$checksum" ]]; then
        echo "Error: $url checksum mismatch! Expected: $checksum, Got: $calculated_checksum"
        exit 1
    fi
done < ./dependencies.txt

echo "Dependencies installed"
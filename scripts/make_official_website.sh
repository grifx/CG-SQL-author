#!/bin/bash

set -o errexit -o nounset -o pipefail

readonly SCRIPT_DIR_RELATIVE=$(dirname "$0")

hugo server --watch --configDir $SCRIPT_DIR_RELATIVE
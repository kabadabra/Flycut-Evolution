#!/bin/bash
set -euo pipefail
[[ $# == 2 ]] || { echo 'Usage: generate-appcast.sh archive-directory download-url-prefix' >&2; exit 2; }
root=$(cd "$(dirname "$0")/.." && pwd)
python3 "$root/scripts/generate-appcast.py" "$1" "$2"

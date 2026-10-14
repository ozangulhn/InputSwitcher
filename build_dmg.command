#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

chmod +x "$SCRIPT_DIR/build_dmg.sh"
"$SCRIPT_DIR/build_dmg.sh"

echo ""
read -p "Kapatmak için Enter'a basın..." _

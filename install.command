#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

chmod +x "$SCRIPT_DIR/install.sh"
"$SCRIPT_DIR/install.sh"

echo ""
read -p "Kapatmak için Enter'a basın..." _

#!/bin/sh

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$PROJECT_DIR/.env" ]; then
	set -a
	# shellcheck disable=SC1090
	. "$PROJECT_DIR/.env"
	set +a
fi

#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

cp -R "${HERE}/fixture/." .

#!/bin/sh
set -eu

image="${1:?usage: scripts/update-image.sh IMAGE}"
file="${2:-k8s/server.yaml}"
revision="${GITHUB_SHA:-manual}"

python3 - "$image" "$file" "$revision" <<'PY'
import sys
from pathlib import Path

image, file, revision = sys.argv[1:]
path = Path(file)
text = path.read_text()
lines = text.splitlines()
for index, line in enumerate(lines):
    if line.strip().startswith("frontman-selfhost/image-revision:"):
        indent = line[: len(line) - len(line.lstrip())]
        lines[index] = f'{indent}frontman-selfhost/image-revision: "{revision}"'
    if line.strip().startswith("image: ghcr.io/nelsong6/frontman-selfhost:"):
        indent = line[: len(line) - len(line.lstrip())]
        lines[index] = f"{indent}image: {image}"
path.write_text("\n".join(lines) + "\n")
PY

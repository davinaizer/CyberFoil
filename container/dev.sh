#!/usr/bin/env bash
# Run a command inside the cyberfoil-dev container (devkitPro toolchain) with this repo mounted.
#   container/dev.sh build-image        build the image (once)
#   container/dev.sh build [make args]  build and copy the NRO to dist/ (cyberfoil.nro + cyberfoil-<version>.nro);
#                                       defaults to -j1 because a 2 GiB podman VM OOMs with more; e.g. `build RELEASE=1`
#   container/dev.sh make -j1           plain make inside the container (NRO stays in the repo root)
#   container/dev.sh analyze            clang-tidy + cppcheck on the Switch sources
#   container/dev.sh bash               interactive shell
# Plutonium is a git submodule; if it is not checked out it is cloned at the pinned commit
# into container/.cache/Plutonium and mounted over include/Plutonium (repo tree stays untouched).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE=cyberfoil-dev
PLU_COMMIT="$(git -C "$ROOT" ls-tree HEAD include/Plutonium | awk '{print $3}')"
MOUNTS=(-v "$ROOT":/src)

if [ "${1:-}" = "build-image" ]; then
  exec podman build -t "$IMAGE" -f "$ROOT/container/Containerfile" "$ROOT/container"
fi

if [ ! -e "$ROOT/include/Plutonium/Plutonium/Makefile" ]; then
  PLU="$ROOT/container/.cache/Plutonium"
  if [ ! -d "$PLU/.git" ]; then
    git clone -q https://github.com/luketanti/Plutonium.git "$PLU"
  fi
  git -C "$PLU" checkout -q "$PLU_COMMIT"
  MOUNTS+=(-v "$PLU":/src/include/Plutonium)
fi

if [ "${1:-}" = "analyze" ]; then
  set -- bash -c '
    set -e; cd /src
    [ -f build-cc.json ] || { rm -rf build; bear --output build-cc.json -- make -j1; }
    mkdir -p /tmp/cc && bash container/analyze.sh
    FILES=$(python3 -c "import json;print(*[e[\"file\"] for e in json.load(open(\"/tmp/cc/compile_commands.json\"))])")
    mkdir -p build-analysis
    clang-tidy -p /tmp/cc -quiet --checks="bugprone-*,clang-analyzer-*,performance-*,concurrency-*,-bugprone-easily-swappable-parameters" $FILES > build-analysis/clang_tidy.txt 2>&1 || true
    cppcheck --project=/tmp/cc/compile_commands.json --enable=warning,performance,portability --inconclusive -j2 \
      --suppress=missingIncludeSystem --template="{file}:{line}:{severity}:{id}:{message}" 2> build-analysis/cppcheck.txt >/dev/null || true
    echo "reports: build-analysis/clang_tidy.txt build-analysis/cppcheck.txt"'
fi

if [ "${1:-}" = "build" ]; then
  shift
  JOBS=(-j1); for a in "$@"; do case "$a" in -j*) JOBS=();; esac; done
  podman run --rm "${MOUNTS[@]}" "$IMAGE" make ${JOBS[@]+"${JOBS[@]}"} "$@"
  VERSION="$(awk -F'[[:space:]]*:=[[:space:]]*' '/^APP_VERSION/ {print $2; exit}' "$ROOT/Makefile")"
  mkdir -p "$ROOT/dist"
  cp "$ROOT/cyberfoil.nro" "$ROOT/dist/cyberfoil.nro"
  cp "$ROOT/cyberfoil.nro" "$ROOT/dist/cyberfoil-$VERSION.nro"
  echo "NRO: $ROOT/dist/cyberfoil-$VERSION.nro"
  exit 0
fi

TTY=(); [ -t 0 ] && TTY=(-it)
exec podman run --rm ${TTY[@]+"${TTY[@]}"} "${MOUNTS[@]}" "$IMAGE" "$@"

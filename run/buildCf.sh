#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
system_libs=/usr/lib/x86_64-linux-gnu
for library in libstdc++.so.6 libgcc_s.so.1; do
    if [[ ! -f "$system_libs/$library" ]]; then
        printf 'Не найдена системная библиотека: %s\n' "$system_libs/$library" >&2
        exit 1
    fi
done

export LD_PRELOAD="$system_libs/libstdc++.so.6:$system_libs/libgcc_s.so.1${LD_PRELOAD:+:$LD_PRELOAD}"
exec pwsh -NoLogo -NoProfile -File "$script_dir/buildCf.ps1" "$@"

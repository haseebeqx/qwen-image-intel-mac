#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

check() {
    if "$@" >/dev/null 2>&1; then printf 'ok    %s\n' "$*"; else printf 'FAIL  %s\n' "$*"; fail=1; fi
}

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != x86_64 ]]; then
    echo "FAIL  expected an Intel macOS host (found $(uname -s) $(uname -m))"
    fail=1
else
    echo "ok    Intel macOS host"
fi

for tool in git cmake curl xcrun; do check command -v "$tool"; done

os_major="$(sw_vers -productVersion | cut -d. -f1)"
if (( os_major < 14 )); then echo "FAIL  macOS 14+ required"; fail=1; else echo "ok    macOS $(sw_vers -productVersion)"; fi

ram_bytes="$(sysctl -n hw.memsize)"
ram_gib=$((ram_bytes / 1024 / 1024 / 1024))
if (( ram_gib < 15 )); then echo "FAIL  ${ram_gib} GiB RAM (16 GiB required)"; fail=1; else echo "ok    ${ram_gib} GiB RAM"; fi

gpu_info="$(system_profiler SPDisplaysDataType 2>/dev/null || true)"
gpu_record="$(awk '
    /Chipset Model:/ {
        amd = ($0 ~ /(AMD|Radeon)/)
        if (amd) {
            name = $0
            sub(/^.*:[[:space:]]*/, "", name)
        }
    }
    amd && /VRAM \(Total\):/ {
        vram = $0
        sub(/^.*:[[:space:]]*/, "", vram)
        split(vram, fields, /[[:space:]]+/)
        amount = fields[1] + 0
        unit = toupper(fields[2])
        mib = (unit ~ /^GB/) ? amount * 1024 : amount
    }
    amd && /Metal Support:/ { metal = 1 }
    amd && name && mib && metal { printf "%s\t%s\t%d\n", name, vram, mib; exit }
' <<<"$gpu_info")"
if [[ -n "$gpu_record" ]]; then
    IFS=$'\t' read -r gpu vram vram_mib <<<"$gpu_record"
    if (( vram_mib < 4096 )); then
        echo "FAIL  $gpu ($vram) has less than the required 4 GB VRAM"
        fail=1
    else
        echo "ok    $gpu ($vram), Metal supported"
    fi
else
    echo "FAIL  no Metal-capable AMD Radeon detected"
    fail=1
fi

free_kib="$(df -Pk "$ROOT" | awk 'NR==2 {print $4}')"
free_gib=$((free_kib / 1024 / 1024))
if (( free_gib < 18 )); then echo "WARN  ${free_gib} GiB disk free; about 20 GiB recommended"; else echo "ok    ${free_gib} GiB disk free"; fi

if [[ -x "$ROOT/build/bin/sd-cli" ]]; then
    echo "ok    engine built"
    "$ROOT/build/bin/sd-cli" --list-devices
else
    echo "info  engine not built; run ./scripts/build.sh"
fi

exit "$fail"

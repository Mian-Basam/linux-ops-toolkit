#!/usr/bin/env bash
# backup.sh - compressed, checksummed backups with retention.
#
# Usage: backup.sh -s SOURCE_DIR -d DEST_DIR [-k KEEP] [-e EXCLUDE_PATTERN]...
#        backup.sh --verify ARCHIVE
#   KEEP   number of most recent archives to keep for this source (default 7)
set -Eeuo pipefail
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
require_cmd tar sha256sum

SRC=""; DEST=""; KEEP=7; EXCLUDES=()

verify() {
  local a="$1"
  [[ -f "$a" && -f "$a.sha256" ]] || die "archive or checksum missing for $a"
  (cd "$(dirname "$a")" && sha256sum -c --quiet "$(basename "$a").sha256") || die "checksum mismatch: $a"
  tar -tzf "$a" >/dev/null || die "archive is corrupt: $a"
  log "verified OK: $a"
}

while (( $# )); do
  case "$1" in
    -s) SRC="$2"; shift ;;
    -d) DEST="$2"; shift ;;
    -k) KEEP="$2"; shift ;;
    -e) EXCLUDES+=("--exclude=$2"); shift ;;
    --verify) verify "$2"; exit 0 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

[[ -d "$SRC" ]] || die "source directory not found: ${SRC:-<unset>}"
[[ -n "$DEST" ]] || die "destination (-d) is required"
[[ "$KEEP" =~ ^[0-9]+$ && "$KEEP" -ge 1 ]] || die "-k must be a positive integer"
mkdir -p "$DEST"

name="$(basename "$(readlink -f "$SRC")")"
archive="$DEST/${name}_$(date +%Y%m%d_%H%M%S).tar.gz"
tmp="$archive.partial"
trap 'rm -f "$tmp"; err "backup failed"; send_alert "backup of $SRC FAILED"' ERR

log "backing up $SRC -> $archive"
tar -czf "$tmp" "${EXCLUDES[@]}" -C "$(dirname "$(readlink -f "$SRC")")" "$name"
mv "$tmp" "$archive"
(cd "$DEST" && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256")
verify "$archive"
log "size: $(human_bytes "$(stat -c %s "$archive")")"

# retention: keep newest $KEEP archives of this source
mapfile -t old < <(find "$DEST" -maxdepth 1 -name "${name}_*.tar.gz" -printf '%T@ %p\n' \
                    | sort -rn | cut -d' ' -f2- | tail -n +$((KEEP + 1)))
for f in "${old[@]}"; do
  rm -f "$f" "$f.sha256"
  log "pruned old backup: $(basename "$f")"
done
log "done (${#old[@]} pruned, keeping $KEEP)"

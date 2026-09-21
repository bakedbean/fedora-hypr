#!/usr/bin/env bash
# Pin every FROM in the Containerfile to the digest its tag currently resolves to.
# The bases are pinned so CI's registry layer cache hits between weekly refreshes
# (base-main:44 is rebuilt daily; an unpinned FROM would invalidate every cached layer
# on nearly every push). Run by the weekly CI build (which commits the result) and by
# `make bump-base`. Prints the FROM lines that changed; exits 0 either way.
set -euo pipefail
cd "$(dirname "$0")/.."

# FROM <ref>[@sha256:…] [AS name]   → replace the digest (or add one) for each ref
before=$(mktemp); cp Containerfile "$before"; trap 'rm -f "$before"' EXIT
mapfile -t refs < <(sed -nE 's/^FROM ([^@[:space:]]+)(@sha256:[0-9a-f]+)?([[:space:]].*)?$/\1/p' Containerfile)
for ref in "${refs[@]}"; do
  digest=$(skopeo inspect --no-tags "docker://$ref" | jq -r .Digest)
  [[ $digest == sha256:* ]] || { echo "bump-base: could not resolve $ref" >&2; exit 1; }
  # `#` is safe as the sed delimiter: neither refs nor digests contain it
  sed -i -E "s#^FROM ${ref}(@sha256:[0-9a-f]+)?([[:space:]]|\$)#FROM ${ref}@${digest}\2#" Containerfile
done
diff -U0 "$before" Containerfile | grep '^[-+]FROM' || echo "bump-base: already current"

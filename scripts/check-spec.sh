#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
spec=${SDK_SPEC_DIR:-"$root/../sdk-spec"}
node "$spec/scripts/generate.mjs" --target swift --out "$root/Sources/CredflareSDK/Spec.generated.swift" --check
for file in "$spec"/fixtures/*.json "$spec"/fixtures/liveness-traces/*.json "$spec"/fixtures/rejections/*.json; do
  relative=${file#"$spec/fixtures/"}
  cmp -s "$file" "$root/Tests/CredflareSDKTests/Fixtures/$relative" || { echo "Fixture out of date: $relative" >&2; exit 1; }
done
echo "Spec and fixtures are up to date."

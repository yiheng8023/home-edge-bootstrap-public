#!/bin/sh
# Build a pinned, static YAML bridge; no compiler is installed on the router.
set -eu
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
out=${1:-"$repo/.tmp/subscription-parser"}
mkdir -p "$out"
out=$(CDPATH= cd "$out" && pwd)
cd "$repo/tools/yamlbridge"
go mod verify
go test ./...
for arch in arm64 amd64; do
  CGO_ENABLED=0 GOOS=linux GOARCH=$arch go build -buildvcs=false -trimpath -ldflags='-s -w -buildid=' -o "$out/yamlbridge-linux-$arch" .
  gzip -n -c "$out/yamlbridge-linux-$arch" > "$out/yamlbridge-linux-$arch.gz"
done
printf 'subscription_parser_build=ok\n'

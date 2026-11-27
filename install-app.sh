#!/bin/zsh
set -eu
destination="${1:-/Applications}"
archive="${0:A:h}/build/dot-bridge-macos.zip"
if [[ ! -d "$destination" || -e "$destination/dot-bridge.app" ]]; then
  print -u2 "Choose an existing directory without a dot-bridge.app: dot-bridge-install-app [directory]"
  exit 1
fi
staging=$(mktemp -d "$destination/.dot-bridge.XXXXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto -x -k "$archive" "$staging"
codesign --verify --deep --strict "$staging/dot-bridge.app"
mv -n "$staging/dot-bridge.app" "$destination/"
[[ ! -e "$staging/dot-bridge.app" ]]
print "Installed $destination/dot-bridge.app"

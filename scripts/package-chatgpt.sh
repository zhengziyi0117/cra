#!/bin/bash
# Bundle the official local DevKit and a CPU-matched Node. No runtime install or shell PATH is needed.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
app="$1"
rev=0a36fefeb913055c8c7a1a29b63d82b96b2e841a
sdk="$root/vendor/chatgpt/$rev"
case "${2:-$(uname -m)}" in
  arm64) cpu=arm64; sha=6a9724d9b50a5f22b4816cded441b5a8d9ddae546191a5e5b7efa5a5e2ee26d5 ;;
  x86_64) cpu=x64; sha=495e3f273c645f3c4677d438304cdfc701729ea5dec5728f5c8e76a2dece4b91 ;;
  *) exit 1 ;;
esac
mkdir -p "$sdk" "$app/Contents/MacOS" "$app/Contents/Resources/chatgpt"
if [ ! -f "$sdk/package-lock.json" ]; then
  if git -C ../sign-in-with-chatgpt-devkit cat-file -e "$rev^{commit}" 2>/dev/null; then
    git -C ../sign-in-with-chatgpt-devkit archive "$rev" | tar xf - -C "$sdk"
  else
    git -C "$sdk" init -q
    git -C "$sdk" fetch -q --depth 1 https://github.com/openai/sign-in-with-chatgpt-devkit.git "$rev"
    git -C "$sdk" checkout -q --detach "$rev"
  fi
fi
if [ ! -f "$sdk/.installed" ]; then
  (cd "$sdk" && npm ci --registry=https://registry.npmjs.org --include=dev --ignore-scripts --no-audit --no-fund --workspace @siwc/local --workspace @siwc/paste-perfect)
  touch "$sdk/.installed"
fi
resources="$app/Contents/Resources/chatgpt"
"$sdk/node_modules/.bin/esbuild" scripts/chatgpt/helper.mjs --platform=node --format=cjs --target=node24 \
  --alias:@siwc/local="$sdk/packages/local/src/index.ts" \
  --bundle --outfile="$resources/helper.cjs"
cp "$sdk/LICENSE" "$sdk/THIRD_PARTY_NOTICES.md" "$resources/"
node="node-v24.22.0-darwin-$cpu"
cache="$root/vendor/chatgpt/$node"
if [ ! -x "$cache/bin/node" ]; then
  tmp=$(mktemp -d "$root/vendor/chatgpt/node.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --retry 2 "https://nodejs.org/dist/v24.22.0/$node.tar.gz" -o "$tmp/node.tgz"
  echo "$sha  $tmp/node.tgz" | shasum -a 256 -c -
  tar xzf "$tmp/node.tgz" -C "$tmp" "$node/bin/node" "$node/LICENSE"
  mv "$tmp/$node" "$cache"
fi
cp "$cache/LICENSE" "$resources/Node-LICENSE"
cp "$cache/bin/node" "$app/Contents/MacOS/CraMaxNode"

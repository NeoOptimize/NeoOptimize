#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -d "$ROOT/.git" ]; then
  DEFAULT_WORKTREE="$ROOT"
else
  DEFAULT_WORKTREE="$ROOT/.github-release-worktree"
fi
WORKTREE="${WORKTREE:-$DEFAULT_WORKTREE}"
REPO="${GITHUB_REPOSITORY:-NeoOptimize/NeoOptimize}"
TAG="${TAG:-v1.0}"
RELEASE_NAME="${RELEASE_NAME:-NeoOptimize v1.0}"
INSTALLER="${INSTALLER:-$ROOT/release/windows/NeoOptimize.exe}"
SOURCE_SHA_FILE="${SOURCE_SHA_FILE:-$ROOT/release/windows/NeoOptimize.exe.sha256}"
UPLOAD_SHA_FILE="${UPLOAD_SHA_FILE:-$ROOT/release/github/NeoOptimize.exe.sha256}"
NOTES_FILE="${NOTES_FILE:-$ROOT/release/github/v1.0-notes.md}"
PUBLISHED_JSON="${PUBLISHED_JSON:-$ROOT/release/github/v1.0-published.json}"
CLEANUP_OLD=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  tools/publish_github_release_v1.0.sh [--cleanup-old] [--dry-run]

What it does:
  1. Verifies the local v1.0 commit/tag and installer checksum.
  2. Prompts for a GitHub token if GITHUB_TOKEN/GH_TOKEN is not set.
  3. Pushes main and tag v1.0 to NeoOptimize/NeoOptimize.
  4. Creates or updates GitHub Release v1.0.
  5. Uploads NeoOptimize.exe and NeoOptimize.exe.sha256.
  6. Verifies the public release assets.
  7. Optionally removes conservative stale local release artifacts with --cleanup-old.

Token requirements:
  - Fine-grained PAT: Contents: Read and write on NeoOptimize/NeoOptimize.
  - Classic PAT: public_repo for a public repository.

The token is never written to git remote URLs or repository files.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --cleanup-old) CLEANUP_OLD=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd git
need_cmd python3
need_cmd sha256sum

[ -d "$WORKTREE/.git" ] || { echo "GitHub worktree not found: $WORKTREE" >&2; exit 1; }
[ -f "$INSTALLER" ] || { echo "Installer not found: $INSTALLER" >&2; exit 1; }
[ -f "$SOURCE_SHA_FILE" ] || { echo "Checksum file not found: $SOURCE_SHA_FILE" >&2; exit 1; }
[ -f "$NOTES_FILE" ] || { echo "Release notes not found: $NOTES_FILE" >&2; exit 1; }

current_branch="$(git -C "$WORKTREE" branch --show-current)"
[ "$current_branch" = "main" ] || { echo "Expected worktree branch main, got: $current_branch" >&2; exit 1; }

local_head="$(git -C "$WORKTREE" rev-parse HEAD)"
tag_head="$(git -C "$WORKTREE" rev-list -n 1 "$TAG" 2>/dev/null || true)"
[ -n "$tag_head" ] || { echo "Local tag missing: $TAG" >&2; exit 1; }
[ "$local_head" = "$tag_head" ] || {
  echo "Tag $TAG does not point to current HEAD." >&2
  echo "HEAD: $local_head" >&2
  echo "$TAG: $tag_head" >&2
  exit 1
}

actual_sha="$(sha256sum "$INSTALLER" | awk '{print $1}')"
source_sha="$(awk '{print $1}' "$SOURCE_SHA_FILE")"
[ "$actual_sha" = "$source_sha" ] || {
  echo "Installer checksum mismatch." >&2
  echo "Actual: $actual_sha" >&2
  echo "File:   $source_sha" >&2
  exit 1
}

mkdir -p "$(dirname "$UPLOAD_SHA_FILE")"
printf '%s  NeoOptimize.exe\n' "$actual_sha" > "$UPLOAD_SHA_FILE"

if [ "$DRY_RUN" -eq 1 ]; then
  cat <<EOF
Dry run OK.
Repo:        $REPO
Worktree:    $WORKTREE
Commit:      $local_head
Tag:         $TAG
Installer:   $INSTALLER
SHA-256:     $actual_sha
Release:     https://github.com/$REPO/releases/tag/$TAG
EOF
  exit 0
fi

token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [ -z "$token" ]; then
  printf 'GitHub token for %s: ' "$REPO" >&2
  if [ -t 0 ]; then
    stty -echo
    IFS= read -r token
    stty echo
  else
    IFS= read -r token
  fi
  printf '\n' >&2
fi
[ -n "$token" ] || { echo "GitHub token is empty." >&2; exit 1; }

askpass="$(mktemp)"
cleanup_secret() {
  rm -f "$askpass"
  unset GITHUB_TOKEN GH_TOKEN token
}
trap cleanup_secret EXIT

cat > "$askpass" <<'SH'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' 'x-access-token' ;;
  *Password*) printf '%s\n' "$GITHUB_TOKEN" ;;
  *) printf '\n' ;;
esac
SH
chmod 700 "$askpass"

export GITHUB_TOKEN="$token"
export GIT_ASKPASS="$askpass"
export GIT_TERMINAL_PROMPT=0
export ROOT REPO TAG RELEASE_NAME INSTALLER UPLOAD_SHA_FILE NOTES_FILE PUBLISHED_JSON

echo "[1/5] Pushing main and refreshing $TAG..."
git -C "$WORKTREE" push origin main
git -C "$WORKTREE" push --force-with-lease origin "$TAG"

echo "[2/5] Creating/updating GitHub release and assets..."
python3 - <<'PY'
import json
import mimetypes
import os
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

token = os.environ["GITHUB_TOKEN"]
repo = os.environ.get("REPO", "NeoOptimize/NeoOptimize")
tag = os.environ.get("TAG", "v1.0")
release_name = os.environ.get("RELEASE_NAME", "NeoOptimize v1.0")
root = pathlib.Path(os.environ.get("ROOT", ".")).resolve()
notes_file = pathlib.Path(os.environ["NOTES_FILE"])
published_json = pathlib.Path(os.environ["PUBLISHED_JSON"])
assets = [
    pathlib.Path(os.environ["INSTALLER"]),
    pathlib.Path(os.environ["UPLOAD_SHA_FILE"]),
]
api = "https://api.github.com"
headers = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {token}",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "NeoOptimize-release-publisher",
}

def request(method, url, data=None, extra_headers=None):
    h = dict(headers)
    body = None
    if isinstance(data, (dict, list)):
        body = json.dumps(data).encode("utf-8")
        h["Content-Type"] = "application/json"
    elif isinstance(data, (bytes, bytearray)):
        body = bytes(data)
    elif data is not None:
        body = data
    if extra_headers:
        h.update(extra_headers)
    req = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=180) as response:
            raw = response.read()
            if not raw:
                return None
            ctype = response.headers.get("Content-Type", "")
            if "json" in ctype:
                return json.loads(raw.decode("utf-8"))
            return raw
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", "replace")
        raise SystemExit(f"{method} {url} failed: HTTP {exc.code}: {raw[:1000]}")

def get_optional(url):
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None
        raw = exc.read().decode("utf-8", "replace")
        raise SystemExit(f"GET {url} failed: HTTP {exc.code}: {raw[:1000]}")

notes = notes_file.read_text(encoding="utf-8")
release = get_optional(f"{api}/repos/{repo}/releases/tags/{tag}")
payload = {
    "tag_name": tag,
    "target_commitish": "main",
    "name": release_name,
    "body": notes,
    "draft": False,
    "prerelease": False,
}
if release is None:
    release = request("POST", f"{api}/repos/{repo}/releases", payload)
else:
    release = request("PATCH", f"{api}/repos/{repo}/releases/{release['id']}", payload)

for asset in list(release.get("assets", [])):
    if asset["name"] in {p.name for p in assets}:
        request("DELETE", asset["url"])

for asset in assets:
    blob = asset.read_bytes()
    ctype = mimetypes.guess_type(asset.name)[0] or "application/octet-stream"
    query = urllib.parse.urlencode({"name": asset.name})
    upload_url = f"https://uploads.github.com/repos/{repo}/releases/{release['id']}/assets?{query}"
    request("POST", upload_url, blob, {
        "Content-Type": ctype,
        "Content-Length": str(len(blob)),
    })

try:
    request("PATCH", f"{api}/repos/{repo}", {
        "homepage": f"https://github.com/{repo}/releases/latest",
    })
except SystemExit as exc:
    print(f"[WARN] Could not update repository homepage: {exc}", file=sys.stderr)

verified = request("GET", f"{api}/repos/{repo}/releases/tags/{tag}")
asset_summary = [(asset["name"], asset["size"], asset["browser_download_url"]) for asset in verified.get("assets", [])]
published = {
    "release": verified["html_url"],
    "tag": verified["tag_name"],
    "assets": asset_summary,
}
published_json.write_text(json.dumps(published, indent=2) + "\n", encoding="utf-8")
print(json.dumps(published, indent=2))
PY

echo "[3/5] Verifying remote refs..."
remote_head="$(git ls-remote "https://github.com/$REPO.git" refs/heads/main | awk '{print $1}')"
remote_tag="$(git ls-remote "https://github.com/$REPO.git" "refs/tags/$TAG^{}" | awk '{print $1}')"
if [ -z "$remote_tag" ]; then
  remote_tag="$(git ls-remote "https://github.com/$REPO.git" "refs/tags/$TAG" | awk '{print $1}')"
fi
[ "$remote_head" = "$local_head" ] || { echo "Remote main mismatch: $remote_head != $local_head" >&2; exit 1; }
[ -n "$remote_tag" ] || { echo "Remote tag missing: $TAG" >&2; exit 1; }

echo "[4/5] Verifying release asset checksum..."
python3 - <<'PY'
import hashlib
import json
import pathlib
import urllib.request
import os

published = json.loads(pathlib.Path(os.environ["PUBLISHED_JSON"]).read_text(encoding="utf-8"))
assets = {name: url for name, _size, url in published["assets"]}
required = {"NeoOptimize.exe", "NeoOptimize.exe.sha256"}
missing = sorted(required - set(assets))
if missing:
    raise SystemExit(f"Missing release assets: {missing}")

with urllib.request.urlopen(assets["NeoOptimize.exe"], timeout=180) as response:
    digest = hashlib.sha256(response.read()).hexdigest()
expected = pathlib.Path(os.environ["UPLOAD_SHA_FILE"]).read_text(encoding="utf-8").split()[0]
if digest != expected:
    raise SystemExit(f"Release asset SHA mismatch: {digest} != {expected}")
print(f"Release asset SHA verified: {digest}")
PY

cleanup_old_artifacts() {
  echo "[5/5] Cleaning conservative stale local artifacts..."
  local removed=0
  local candidates=(
    "$ROOT/release/windows/NeoOptimize-portable.zip"
    "$ROOT/release/windows/NeoOptimize-portable.zip.sha256"
    "$ROOT/release/windows/NeoOptimize.exe.tmp"
    "$ROOT/release/windows/NeoOptimize.exe.old"
    "$ROOT/release/github/NeoOptimize.exe.tmp"
    "$ROOT/release/github/NeoOptimize.exe.old"
    "$ROOT/.github-release-worktree/checksums/NeoOptimize-portable.zip.sha256"
  )
  for path in "${candidates[@]}"; do
    if [ -e "$path" ]; then
      rm -rf -- "$path"
      echo "Removed: $path"
      removed=1
    fi
  done
  if [ "$removed" -eq 0 ]; then
    echo "No conservative stale release artifacts found."
  fi
}

if [ "$CLEANUP_OLD" -eq 1 ]; then
  cleanup_old_artifacts
else
  echo "[5/5] Cleanup skipped. Re-run with --cleanup-old after reviewing release if needed."
fi

echo "Done: https://github.com/$REPO/releases/tag/$TAG"

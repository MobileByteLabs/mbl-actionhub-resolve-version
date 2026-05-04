#!/usr/bin/env bash
# resolve.sh — version resolver core
# Reads env vars (set by action.yml or tests):
#   GROUP_ID, ARTIFACT_ID, BUMP, EXPLICIT_VERSION, VERSION_SOURCE,
#   GP_PATH, GP_KEY, BUMP_WHEN, VERIFY, TAG_PATTERN, GITHUB_TOKEN
# Optional override for tests:
#   GITHUB_OUTPUT  — file to append outputs (default /dev/null in non-CI)
#   MAVEN_LATEST_OVERRIDE  — short-circuit Maven Central query (testing)
#   GH_RELEASES_JSON_OVERRIDE  — short-circuit GH Releases query (testing)

set -euo pipefail

: "${GROUP_ID:?required}"
: "${ARTIFACT_ID:?required}"
: "${BUMP:=patch}"
: "${EXPLICIT_VERSION:=}"
: "${VERSION_SOURCE:=auto}"
: "${GP_PATH:=gradle.properties}"
: "${GP_KEY:=}"
: "${BUMP_WHEN:=github-releases,maven-central}"
: "${VERIFY:=true}"
: "${TAG_PATTERN:=^v?[0-9]+\\.[0-9]+\\.[0-9]+$}"
: "${GITHUB_TOKEN:=}"
: "${GITHUB_OUTPUT:=/dev/null}"

if ! command -v jq >/dev/null 2>&1; then
  echo "::error::jq is required but not installed on this runner"
  exit 1
fi

# ── helpers ─────────────────────────────────────────────────────────────────

is_semver() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

bump_version() {
  local v="$1" kind="$2"
  local major minor patch
  IFS=. read -r major minor patch <<<"$v"
  case "$kind" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    *)     echo "${major}.${minor}.$((patch + 1))" ;;
  esac
}

# Compare semvers: prints -1 / 0 / 1 for $1 vs $2
cmp_semver() {
  local a="$1" b="$2"
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<<"$a"
  IFS=. read -r b1 b2 b3 <<<"$b"
  for pair in "$a1 $b1" "$a2 $b2" "$a3 $b3"; do
    read -r av bv <<<"$pair"
    if (( av < bv )); then echo -1; return; fi
    if (( av > bv )); then echo  1; return; fi
  done
  echo 0
}

should_bump() {
  local src="$1"
  [[ ",${BUMP_WHEN}," == *",${src},"* ]]
}

query_maven() {
  # Authoritative source: repo1.maven.org/maven2/.../maven-metadata.xml.
  # Previously used search.maven.org/solrsearch, but Sonatype's Solr index
  # does not reliably index every group (e.g. io.github.mobilebytelabs returns
  # numFound:0), causing the sanity check to silently pass. The repo metadata
  # XML is canonical and updated immediately on publish.
  if [ -n "${MAVEN_LATEST_OVERRIDE:-}" ]; then
    echo "$MAVEN_LATEST_OVERRIDE"
    return
  fi
  local xml
  if [ -n "${MAVEN_METADATA_XML_OVERRIDE:-}" ]; then
    xml="$MAVEN_METADATA_XML_OVERRIDE"
  else
    local group_path="${GROUP_ID//.//}"
    local url="https://repo1.maven.org/maven2/${group_path}/${ARTIFACT_ID}/maven-metadata.xml"
    xml=$(curl -sf "$url" 2>/dev/null) || true
    [ -z "$xml" ] && return 0
  fi
  # Prefer <release>, fall back to <latest>. Both should match for non-snapshot
  # publishes.
  local v
  v=$(echo "$xml" | sed -n 's|.*<release>\([^<]*\)</release>.*|\1|p' | head -1)
  [ -z "$v" ] && v=$(echo "$xml" | sed -n 's|.*<latest>\([^<]*\)</latest>.*|\1|p' | head -1)
  echo "$v"
}

query_github_releases() {
  if [ -n "${GH_RELEASES_JSON_OVERRIDE:-}" ]; then
    echo "$GH_RELEASES_JSON_OVERRIDE"
    return
  fi
  local repo="${GITHUB_REPOSITORY:-}"
  [ -z "$repo" ] && return 0
  curl -sf -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/releases?per_page=100" 2>/dev/null || true
}

# ── sources ─────────────────────────────────────────────────────────────────

try_explicit() {
  [ -z "$EXPLICIT_VERSION" ] && return 1
  local v="${EXPLICIT_VERSION#v}"
  if ! is_semver "$v"; then
    echo "::error::Explicit version '$EXPLICIT_VERSION' is not valid semver X.Y.Z"
    return 2
  fi
  RESOLVED_RAW="$v"
  RESOLVED_SRC="explicit"
  return 0
}

try_gradle() {
  [ -z "$GP_KEY" ] && return 1
  [ ! -f "$GP_PATH" ] && return 1
  local v
  v=$(grep -E "^[[:space:]]*${GP_KEY}[[:space:]]*=" "$GP_PATH" | head -n1 | cut -d= -f2- | xargs || true)
  [ -z "$v" ] && return 1
  v="${v#v}"
  if ! is_semver "$v"; then
    echo "::warning::gradle.properties key '$GP_KEY' value '$v' is not valid semver — skipping"
    return 1
  fi
  RESOLVED_RAW="$v"
  RESOLVED_SRC="gradle-properties"
  return 0
}

try_github() {
  local json
  json=$(query_github_releases)
  [ -z "$json" ] && return 1
  local tags
  tags=$(echo "$json" | jq -r '.[]? | select(.draft==false and .prerelease==false) | .tag_name' 2>/dev/null || true)
  [ -z "$tags" ] && return 1
  local best=""
  while IFS= read -r tag; do
    [ -z "$tag" ] && continue
    [[ "$tag" =~ $TAG_PATTERN ]] || continue
    local v="${tag#v}"
    is_semver "$v" || continue
    if [ -z "$best" ] || [ "$(cmp_semver "$v" "$best")" = "1" ]; then
      best="$v"
    fi
  done <<<"$tags"
  [ -z "$best" ] && return 1
  RESOLVED_RAW="$best"
  RESOLVED_SRC="github-releases"
  return 0
}

try_maven() {
  local v
  v=$(query_maven)
  [ -z "$v" ] && return 1
  is_semver "$v" || return 1
  RESOLVED_RAW="$v"
  RESOLVED_SRC="maven-central"
  return 0
}

# ── resolve in priority order ───────────────────────────────────────────────

RESOLVED_RAW=""
RESOLVED_SRC=""

run_chain() {
  try_explicit && return 0
  local rc=$?; [ "$rc" = "2" ] && return 2
  try_gradle  && return 0
  try_github  && return 0
  try_maven   && return 0
  return 1
}

case "$VERSION_SOURCE" in
  explicit)          try_explicit || true ;;
  gradle-properties) try_gradle   || true ;;
  github-releases)   try_github   || true ;;
  maven-central)     try_maven    || true ;;
  auto|*)            run_chain    || true ;;
esac

if [ -z "$RESOLVED_RAW" ]; then
  echo "::error::Could not resolve version from any source (explicit='$EXPLICIT_VERSION', gradle-key='$GP_KEY', github-releases, maven-central=${GROUP_ID}:${ARTIFACT_ID})"
  exit 1
fi

# ── bump if applicable ──────────────────────────────────────────────────────

if should_bump "$RESOLVED_SRC"; then
  NEW_VERSION=$(bump_version "$RESOLVED_RAW" "$BUMP")
else
  NEW_VERSION="$RESOLVED_RAW"
fi

# ── sanity check against Maven Central ──────────────────────────────────────

if [ "$VERIFY" = "true" ]; then
  MAVEN_LATEST=$(query_maven || echo "")
  if [ -n "$MAVEN_LATEST" ] && is_semver "$MAVEN_LATEST"; then
    cmp=$(cmp_semver "$NEW_VERSION" "$MAVEN_LATEST")
    if [ "$cmp" != "1" ]; then
      echo "::error::Sanity check failed: resolved ${NEW_VERSION} is not greater than latest on Maven Central (${MAVEN_LATEST}) for ${GROUP_ID}:${ARTIFACT_ID}. source=${RESOLVED_SRC} raw=${RESOLVED_RAW} bump=${BUMP}. Likely a deleted GH tag, a downgraded gradle.properties, or a stale anchor."
      exit 1
    fi
  fi
fi

echo "current=${RESOLVED_RAW}" >> "$GITHUB_OUTPUT"
echo "version=${NEW_VERSION}" >> "$GITHUB_OUTPUT"
echo "source=${RESOLVED_SRC}" >> "$GITHUB_OUTPUT"
echo "Resolved: source=${RESOLVED_SRC} raw=${RESOLVED_RAW} → next=${NEW_VERSION} (bump=${BUMP}, bump-when=${BUMP_WHEN})"

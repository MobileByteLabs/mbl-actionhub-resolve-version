#!/usr/bin/env bash
# Test runner for resolve.sh
# Each test sets env vars, runs resolve.sh in a temp dir, asserts outputs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE="${SCRIPT_DIR}/../resolve.sh"

PASS_FILE="$(mktemp)"
FAIL_FILE="$(mktemp)"
NAMES_FILE="$(mktemp)"
echo 0 > "$PASS_FILE"
echo 0 > "$FAIL_FILE"
trap 'rm -f "$PASS_FILE" "$FAIL_FILE" "$NAMES_FILE"' EXIT

bump_pass() { echo $(( $(cat "$PASS_FILE") + 1 )) > "$PASS_FILE"; }
bump_fail() { echo $(( $(cat "$FAIL_FILE") + 1 )) > "$FAIL_FILE"; echo "$1" >> "$NAMES_FILE"; }

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ✓ ${name}"
    bump_pass
  else
    echo "  ✗ ${name}: expected '${expected}', got '${actual}'"
    bump_fail "${name}"
  fi
}

run_resolver() {
  # Args: descriptive name, pass env via caller's exported vars
  # Outputs `current=`, `version=`, `source=` written to $GITHUB_OUTPUT
  local out
  out="$(mktemp)"
  GITHUB_OUTPUT="$out" bash "$RESOLVE" >/dev/null 2>&1 || true
  cat "$out"
  rm -f "$out"
}

run_resolver_capture_err() {
  local out err rc
  out="$(mktemp)"; err="$(mktemp)"
  GITHUB_OUTPUT="$out" bash "$RESOLVE" >/dev/null 2>"$err"
  rc=$?
  echo "RC=${rc}"
  cat "$err"
  rm -f "$out" "$err"
  return 0
}

# Common defaults (override in each test)
export GROUP_ID="io.github.mobilebytelabs"
export ARTIFACT_ID="cmp-bubble"
export BUMP="patch"
export VERIFY="false"      # tests turn this on selectively
export TAG_PATTERN='^v?[0-9]+\.[0-9]+\.[0-9]+$'
export BUMP_WHEN="github-releases,maven-central"
export MAVEN_LATEST_OVERRIDE=""
export GH_RELEASES_JSON_OVERRIDE=""

# ─── Test 1: explicit version, no bump ───────────────────────────────────────
echo "Test 1: explicit version → as-is"
{
  unset MAVEN_LATEST_OVERRIDE GH_RELEASES_JSON_OVERRIDE EXPLICIT_VERSION GP_KEY GP_PATH BUMP BUMP_WHEN VERIFY VERSION_SOURCE 2>/dev/null || true
  export BUMP=patch BUMP_WHEN="github-releases,maven-central" VERIFY="false" VERSION_SOURCE="auto"
  export EXPLICIT_VERSION="3.2.2"
  export VERSION_SOURCE="auto"
  export GP_KEY=""
  out=$(run_resolver)
  assert_eq "explicit/version"  "version=3.2.2" "$(echo "$out" | grep '^version=')"
  assert_eq "explicit/current"  "current=3.2.2" "$(echo "$out" | grep '^current=')"
  assert_eq "explicit/source"   "source=explicit" "$(echo "$out" | grep '^source=')"
}

# ─── Test 2: gradle.properties, no bump by default ───────────────────────────
echo "Test 2: gradle.properties → as-is"
{
  unset MAVEN_LATEST_OVERRIDE GH_RELEASES_JSON_OVERRIDE EXPLICIT_VERSION GP_KEY GP_PATH BUMP BUMP_WHEN VERIFY VERSION_SOURCE 2>/dev/null || true
  export BUMP=patch BUMP_WHEN="github-releases,maven-central" VERIFY="false" VERSION_SOURCE="auto"
  TMP=$(mktemp -d)
  echo "kmptoolkit.version=3.2.1" > "${TMP}/gradle.properties"
  echo "other.thing=ignored" >> "${TMP}/gradle.properties"
  export EXPLICIT_VERSION=""
  export VERSION_SOURCE="auto"
  export GP_PATH="${TMP}/gradle.properties"
  export GP_KEY="kmptoolkit.version"
  out=$(run_resolver)
  assert_eq "gradle/version" "version=3.2.1" "$(echo "$out" | grep '^version=')"
  assert_eq "gradle/source"  "source=gradle-properties" "$(echo "$out" | grep '^source=')"
  rm -rf "$TMP"
}

# ─── Test 3: gradle.properties WITH bump-when override ───────────────────────
echo "Test 3: gradle.properties + bump-when → bumped"
{
  unset MAVEN_LATEST_OVERRIDE GH_RELEASES_JSON_OVERRIDE EXPLICIT_VERSION GP_KEY GP_PATH BUMP BUMP_WHEN VERIFY VERSION_SOURCE 2>/dev/null || true
  export BUMP=patch BUMP_WHEN="github-releases,maven-central" VERIFY="false" VERSION_SOURCE="auto"
  TMP=$(mktemp -d)
  echo "kmptoolkit.version=3.2.1" > "${TMP}/gradle.properties"
  export EXPLICIT_VERSION=""
  export VERSION_SOURCE="auto"
  export GP_PATH="${TMP}/gradle.properties"
  export GP_KEY="kmptoolkit.version"
  export BUMP_WHEN="gradle-properties"
  out=$(run_resolver)
  assert_eq "gradle-bump/version" "version=3.2.2" "$(echo "$out" | grep '^version=')"
  assert_eq "gradle-bump/current" "current=3.2.1" "$(echo "$out" | grep '^current=')"
  rm -rf "$TMP"
}

# ─── Test 4: GitHub Releases — picks highest matching, filters non-semver ────
echo "Test 4: GitHub Releases → highest semver, bumped"
{
  unset MAVEN_LATEST_OVERRIDE GH_RELEASES_JSON_OVERRIDE EXPLICIT_VERSION GP_KEY GP_PATH BUMP BUMP_WHEN VERIFY VERSION_SOURCE 2>/dev/null || true
  export BUMP=patch BUMP_WHEN="github-releases,maven-central" VERIFY="false" VERSION_SOURCE="auto"
  export EXPLICIT_VERSION=""
  export VERSION_SOURCE="github-releases"
  export GP_KEY=""
  export GH_RELEASES_JSON_OVERRIDE='[
    {"tag_name":"nightly-260504","draft":false,"prerelease":false},
    {"tag_name":"v3.2.1","draft":false,"prerelease":false},
    {"tag_name":"v3.2.2","draft":false,"prerelease":false},
    {"tag_name":"v4.0.0-rc1","draft":false,"prerelease":true},
    {"tag_name":"draft-tag","draft":true,"prerelease":false},
    {"tag_name":"v2.1.3","draft":false,"prerelease":false}
  ]'
  export BUMP_WHEN="github-releases,maven-central"
  out=$(run_resolver)
  assert_eq "gh/version" "version=3.2.3" "$(echo "$out" | grep '^version=')"
  assert_eq "gh/current" "current=3.2.2" "$(echo "$out" | grep '^current=')"
  assert_eq "gh/source"  "source=github-releases" "$(echo "$out" | grep '^source=')"
}

# ─── Test 5: Sanity check FAILS when resolved <= maven ───────────────────────
echo "Test 5: sanity check fails (3.2.0 vs maven 3.2.2)"
{
  unset MAVEN_LATEST_OVERRIDE GH_RELEASES_JSON_OVERRIDE EXPLICIT_VERSION GP_KEY GP_PATH BUMP BUMP_WHEN VERIFY VERSION_SOURCE 2>/dev/null || true
  export BUMP=patch BUMP_WHEN="github-releases,maven-central" VERIFY="false" VERSION_SOURCE="auto"
  TMP=$(mktemp -d)
  echo "kmptoolkit.version=3.2.0" > "${TMP}/gradle.properties"
  export EXPLICIT_VERSION=""
  export VERSION_SOURCE="auto"
  export GP_PATH="${TMP}/gradle.properties"
  export GP_KEY="kmptoolkit.version"
  export VERIFY="true"
  export MAVEN_LATEST_OVERRIDE="3.2.2"
  out_file=$(mktemp); log_file=$(mktemp)
  GITHUB_OUTPUT="$out_file" bash "$RESOLVE" >"$log_file" 2>&1 && rc=$? || rc=$?
  assert_eq "sanity-fail/rc" "1" "$rc"
  if grep -q "Sanity check failed" "$log_file"; then
    echo "  ✓ sanity-fail/message"; bump_pass
  else
    echo "  ✗ sanity-fail/message: missing 'Sanity check failed' in output"
    echo "    log: $(cat "$log_file")"
    bump_fail "sanity-fail/message"
  fi
  rm -rf "$TMP" "$out_file" "$log_file"
}

# ─── Test 6: Sanity check PASSES when resolved > maven ───────────────────────
echo "Test 6: sanity check passes (3.2.3 vs maven 3.2.2)"
{
  unset MAVEN_LATEST_OVERRIDE GH_RELEASES_JSON_OVERRIDE EXPLICIT_VERSION GP_KEY GP_PATH BUMP BUMP_WHEN VERIFY VERSION_SOURCE 2>/dev/null || true
  export BUMP=patch BUMP_WHEN="github-releases,maven-central" VERIFY="false" VERSION_SOURCE="auto"
  export EXPLICIT_VERSION="3.2.3"
  export VERSION_SOURCE="auto"
  export GP_KEY=""
  export VERIFY="true"
  export MAVEN_LATEST_OVERRIDE="3.2.2"
  out=$(run_resolver)
  assert_eq "sanity-pass/version" "version=3.2.3" "$(echo "$out" | grep '^version=')"
}

# ─── Test 7: Maven Central fallback (no other source) ────────────────────────
echo "Test 7: maven-central → patch bumped"
{
  unset MAVEN_LATEST_OVERRIDE GH_RELEASES_JSON_OVERRIDE EXPLICIT_VERSION GP_KEY GP_PATH BUMP BUMP_WHEN VERIFY VERSION_SOURCE 2>/dev/null || true
  export BUMP=patch BUMP_WHEN="github-releases,maven-central" VERIFY="false" VERSION_SOURCE="auto"
  export EXPLICIT_VERSION=""
  export VERSION_SOURCE="maven-central"
  export GP_KEY=""
  export VERIFY="false"
  export MAVEN_LATEST_OVERRIDE="3.2.2"
  out=$(run_resolver)
  assert_eq "maven/version" "version=3.2.3" "$(echo "$out" | grep '^version=')"
  assert_eq "maven/current" "current=3.2.2" "$(echo "$out" | grep '^current=')"
  assert_eq "maven/source"  "source=maven-central" "$(echo "$out" | grep '^source=')"
}

# ─── Test 8: bump=minor / bump=major ─────────────────────────────────────────
echo "Test 8: bump levels"
{
  unset MAVEN_LATEST_OVERRIDE GH_RELEASES_JSON_OVERRIDE EXPLICIT_VERSION GP_KEY GP_PATH BUMP BUMP_WHEN VERIFY VERSION_SOURCE 2>/dev/null || true
  export BUMP=patch BUMP_WHEN="github-releases,maven-central" VERIFY="false" VERSION_SOURCE="auto"
  export EXPLICIT_VERSION=""
  export VERSION_SOURCE="maven-central"
  export GP_KEY=""
  export VERIFY="false"
  export MAVEN_LATEST_OVERRIDE="3.2.2"
  export BUMP="minor"
  out=$(run_resolver)
  assert_eq "bump-minor/version" "version=3.3.0" "$(echo "$out" | grep '^version=')"
  export BUMP="major"
  out=$(run_resolver)
  assert_eq "bump-major/version" "version=4.0.0" "$(echo "$out" | grep '^version=')"
}

# ─── Test 9: invalid explicit version ────────────────────────────────────────
echo "Test 9: invalid explicit version → fail"
{
  unset MAVEN_LATEST_OVERRIDE GH_RELEASES_JSON_OVERRIDE EXPLICIT_VERSION GP_KEY GP_PATH BUMP BUMP_WHEN VERIFY VERSION_SOURCE 2>/dev/null || true
  export BUMP=patch BUMP_WHEN="github-releases,maven-central" VERIFY="false" VERSION_SOURCE="auto"
  export EXPLICIT_VERSION="not-a-version"
  export VERSION_SOURCE="auto"
  export GP_KEY=""
  export VERIFY="false"
  err_file=$(mktemp)
  GITHUB_OUTPUT=/dev/null bash "$RESOLVE" >/dev/null 2>"$err_file" && rc=$? || rc=$?
  assert_eq "invalid-explicit/rc" "1" "$rc"
  rm -f "$err_file"
}

# ─── summary ─────────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────────"
PASS=$(cat "$PASS_FILE")
FAIL=$(cat "$FAIL_FILE")
echo "Results: ${PASS} passed, ${FAIL} failed"
if [ "$FAIL" -gt 0 ]; then
  printf "Failed tests:\n"
  while IFS= read -r n; do echo "  - ${n}"; done < "$NAMES_FILE"
  exit 1
fi

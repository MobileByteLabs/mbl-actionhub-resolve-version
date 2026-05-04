# mbl-actionhub-resolve-version

Resolves the next publish version for a KMP library, with multiple sources and a Maven Central sanity check.

## Resolution chain (priority order)

1. **Explicit input** (`version:`) — used as-is, no bump. Highest priority.
2. **gradle.properties** (when `gradle-properties-key` is set) — read from a committed file. Used as-is by default; the developer-declared value is the source of truth.
3. **GitHub Releases** — highest semver tag matching `tag-pattern`, patch-bumped. Drafts and pre-releases excluded.
4. **Maven Central** — patch-bumped. Last resort.
5. **Sanity check** — verify resolved version is strictly greater than latest on Maven Central; fail loudly otherwise.

The default mode is `auto`, which runs the chain top-to-bottom. Set `version-source` to lock to a specific source (e.g. `gradle-properties`).

## Quick examples

### Recommended: gradle.properties as source of truth

```yaml
- uses: MobileByteLabs/mbl-actionhub-resolve-version@v1.1.0
  id: version
  with:
    group-id: 'io.github.mobilebytelabs'
    artifact-id: 'cmp-bubble'                 # only used for sanity check
    gradle-properties-key: 'kmptoolkit.version'
```

The committed `kmptoolkit.version=3.2.2` becomes the published version. No registry guessing.

### Manual override

```yaml
on:
  workflow_dispatch:
    inputs:
      version: { required: false, type: string }

jobs:
  publish:
    steps:
      - uses: MobileByteLabs/mbl-actionhub-resolve-version@v1.1.0
        id: version
        with:
          group-id: 'io.github.mobilebytelabs'
          artifact-id: 'cmp-bubble'
          version: ${{ inputs.version }}      # if non-empty, used as-is
          gradle-properties-key: 'kmptoolkit.version'
```

### Backward compatible (Maven Central only)

```yaml
- uses: MobileByteLabs/mbl-actionhub-resolve-version@v1.1.0
  with:
    group-id: 'io.github.mobilebytelabs'
    artifact-id: 'cmp-clipboard'
    # no gradle key, no explicit version → falls through to GH Releases → Maven
```

## Inputs

| Input | Required | Default | Description |
|---|:---:|---|---|
| `group-id` | **Yes** | — | Maven group ID |
| `artifact-id` | **Yes** | — | Maven artifact ID (sanity check + Maven source) |
| `bump` | No | `patch` | `patch` / `minor` / `major` |
| `version` | No | `''` | Explicit override (used as-is, no bump) |
| `version-source` | No | `auto` | `auto` / `gradle-properties` / `github-releases` / `maven-central` |
| `gradle-properties-path` | No | `gradle.properties` | Path to properties file |
| `gradle-properties-key` | No | `''` | Key holding the version (e.g. `kmptoolkit.version`). Empty disables source. |
| `bump-when` | No | `github-releases,maven-central` | Comma list of sources whose value gets patch-bumped |
| `verify-against-maven` | No | `true` | Sanity check: resolved must be greater than Maven latest |
| `tag-pattern` | No | `^v?[0-9]+\.[0-9]+\.[0-9]+$` | Tag filter regex |

## Outputs

| Output | Description |
|---|---|
| `version` | Next version to publish |
| `current` | Resolved current version (pre-bump) |
| `source` | Which source was used (`explicit` / `gradle-properties` / `github-releases` / `maven-central`) |

## Why not just Maven Central?

Maven Central is per-artifact. If your toolkit publishes 10 modules together and one lags at `2.1.x` while the rest are on `3.2.x`, picking the lagging one as the "anchor" silently ships every module on the 2.1 track. KmpToolkit hit exactly this in May 2026.

`gradle.properties` is the *input* — committed, reviewable in PRs, atomic with the code being published. Maven and GH Releases are *outputs*. This action lets you treat the input as the source of truth, and uses Maven Central as a downgrade alarm only.

## Sanity check failure example

```
::error::Sanity check failed: resolved 3.2.0 is not greater than latest on Maven Central (3.2.2)
for io.github.mobilebytelabs:cmp-bubble. source=gradle-properties raw=3.2.0 bump=patch.
Likely a deleted GH tag, a downgraded gradle.properties, or a stale anchor.
```

## Testing

`tests/run-tests.sh` covers all sources, bump modes, tag-pattern filtering, and sanity-check success/failure. Runs on every PR via `.github/workflows/test.yml`.

```bash
bash tests/run-tests.sh
```

## Migration from v1.0.5

Backward compatible. Old callers that pass only `group-id`, `artifact-id`, `bump` see identical behavior — the chain falls through to Maven Central.

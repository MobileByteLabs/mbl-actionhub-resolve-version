# mbl-actionhub-resolve-version

Fetches the latest published version from Maven Central and bumps it. No version to manage in your repo.

## Usage

### With explicit coordinates

```yaml
- uses: MobileByteLabs/mbl-actionhub-resolve-version@v1.0.0
  id: version
  with:
    group-id: 'io.github.mobilebytelabs'
    artifact-id: 'cmp-clipboard'

- run: echo "Next version: ${{ steps.version.outputs.version }}"
```

### Auto-detect from build.gradle.kts

```yaml
- uses: actions/checkout@v6

- uses: MobileByteLabs/mbl-actionhub-resolve-version@v1.0.0
  id: version
  with:
    module-pattern: 'cmp-'
```

Scans `cmp-*/build.gradle.kts` for `coordinates("group", "artifact")` and queries Maven Central.

### Bump types

```yaml
- uses: MobileByteLabs/mbl-actionhub-resolve-version@v1.0.0
  with:
    group-id: 'io.github.mobilebytelabs'
    artifact-id: 'cmp-clipboard'
    bump: 'minor'   # patch (default), minor, or major
```

## Inputs

| Input | Required | Default | Description |
|-------|:--------:|---------|-------------|
| `group-id` | No | `''` | Maven group ID. Auto-detected if empty. |
| `artifact-id` | No | `''` | Maven artifact ID. Auto-detected if empty. |
| `module-pattern` | No | `''` | Directory prefix for auto-detection (e.g. `cmp-`). |
| `bump` | No | `patch` | Which part to bump: `patch`, `minor`, or `major`. |

## Outputs

| Output | Description |
|--------|-------------|
| `version` | Next version to publish (e.g. `3.2.2`) |
| `current` | Latest version on Maven Central (e.g. `3.2.1`) |

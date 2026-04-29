# mbl-actionhub-resolve-version

Resolves the next publish version automatically. Zero code to manage.

## How it works

1. **Maven Central** — queries for the latest published version → bumps it
2. **GitHub Releases** — if not yet on Maven Central, uses the latest GitHub Release tag
3. **Error** — if neither exists, fails with a clear message to create a GitHub Release first

## Usage

```yaml
- uses: MobileByteLabs/mbl-actionhub-resolve-version@v1.0.5
  id: version
  with:
    group-id: 'io.github.mobilebytelabs'
    artifact-id: 'cmp-clipboard'

- run: echo "Next version: ${{ steps.version.outputs.version }}"
```

### Bump types

```yaml
- uses: MobileByteLabs/mbl-actionhub-resolve-version@v1.0.5
  with:
    group-id: 'io.github.mobilebytelabs'
    artifact-id: 'cmp-clipboard'
    bump: 'minor'   # patch (default), minor, or major
```

### First publish

Create a GitHub Release (e.g. `v3.2.0`) in your repo. The action reads it and bumps to `3.2.1`.

## Inputs

| Input | Required | Default | Description |
|-------|:--------:|---------|-------------|
| `group-id` | **Yes** | — | Maven group ID |
| `artifact-id` | **Yes** | — | Maven artifact ID |
| `bump` | No | `patch` | Which part to bump: `patch`, `minor`, or `major` |

## Outputs

| Output | Description |
|--------|-------------|
| `version` | Next version to publish (e.g. `3.2.2`) |
| `current` | Current latest version (e.g. `3.2.1`) |

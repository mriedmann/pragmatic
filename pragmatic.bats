#!/usr/bin/env bats
#
# Test suite for pragmatic.sh
#
# To run these tests, install bats-core:
#   https://github.com/bats-core/bats-core
#
# Run tests:
#   bats pragmatic.bats
#
# Run specific test:
#   bats pragmatic.bats -f "basic marker replacement"
#

setup() {
    # Create a temporary directory for test files
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
}

teardown() {
    # Clean up temporary directory
    rm -rf "$TEST_DIR"
}

@test "pragmatic.sh: basic marker replacement with built-in function" {
    cat > "$TEST_DIR/test.yml" <<EOF
default: registry.io/image:old ##! update_image_tag v1.2.3
EOF

    export RELEASE_VERSION=v1.2.3
    run ./pragmatic.sh "$TEST_DIR/test.yml"

    [ "$status" -eq 0 ]
    grep -q "registry.io/image:v1.2.3 ##! update_image_tag v1.2.3" "$TEST_DIR/test.yml"
}

@test "pragmatic.sh: variable expansion in arguments" {
    cat > "$TEST_DIR/test.yml" <<EOF
default: registry.io/image:old ##! update_image_tag \$RELEASE_VERSION
EOF

    export RELEASE_VERSION=v2.0.0
    run ./pragmatic.sh "$TEST_DIR/test.yml"

    [ "$status" -eq 0 ]
    grep -q "registry.io/image:v2.0.0 ##! update_image_tag \$RELEASE_VERSION" "$TEST_DIR/test.yml"
}

@test "pragmatic.sh: external command with sed" {
    cat > "$TEST_DIR/test.yml" <<EOF
value: hello ##! sed 's/hello/world/' <<< "\$1"
EOF

    run ./pragmatic.sh "$TEST_DIR/test.yml"

    [ "$status" -eq 0 ]
    grep -q "value: world ##! sed 's/hello/world/' <<< \"\\\$1\"" "$TEST_DIR/test.yml"
}

@test "pragmatic.sh: auto-append \$1 when not present" {
    cat > "$TEST_DIR/test.yml" <<EOF
value: test ##! printf 'changed'
EOF

    run ./pragmatic.sh "$TEST_DIR/test.yml"

    [ "$status" -eq 0 ]
    grep -q 'changed ##! printf '"'"'changed'"'"' "\$1"' "$TEST_DIR/test.yml"
}

@test "pragmatic.sh: preserve lines without markers" {
    cat > "$TEST_DIR/test.yml" <<EOF
normal_line: value
another: line
default: registry.io/image:old ##! update_image_tag v1.0.0
no_marker: here
EOF

    run ./pragmatic.sh "$TEST_DIR/test.yml"

    [ "$status" -eq 0 ]
    grep -q "normal_line: value" "$TEST_DIR/test.yml"
    grep -q "another: line" "$TEST_DIR/test.yml"
    grep -q "no_marker: here" "$TEST_DIR/test.yml"
}

@test "pragmatic.sh: check mode - no modifications when changes needed" {
    cat > "$TEST_DIR/test.yml" <<EOF
default: registry.io/image:old ##! update_image_tag v1.2.3
EOF

    cp "$TEST_DIR/test.yml" "$TEST_DIR/test.yml.backup"

    run ./pragmatic.sh --check "$TEST_DIR/test.yml"

    [ "$status" -eq 1 ]
    diff "$TEST_DIR/test.yml" "$TEST_DIR/test.yml.backup"
}

@test "pragmatic.sh: check mode - success when no changes needed" {
    cat > "$TEST_DIR/test.yml" <<EOF
default: registry.io/image:v1.2.3 ##! update_image_tag v1.2.3
EOF

    run ./pragmatic.sh --check "$TEST_DIR/test.yml"

    [ "$status" -eq 0 ]
}

@test "pragmatic.sh: check mode - no modifications on multiple files" {
    cat > "$TEST_DIR/file1.yml" <<EOF
default: registry.io/image:old ##! update_image_tag v1.0.0
EOF

    cat > "$TEST_DIR/file2.yml" <<EOF
value: test ##! printf 'changed'
EOF

    cp "$TEST_DIR/file1.yml" "$TEST_DIR/file1.yml.backup"
    cp "$TEST_DIR/file2.yml" "$TEST_DIR/file2.yml.backup"

    run ./pragmatic.sh --check "$TEST_DIR/file1.yml" "$TEST_DIR/file2.yml"

    [ "$status" -eq 1 ]
    diff "$TEST_DIR/file1.yml" "$TEST_DIR/file1.yml.backup"
    diff "$TEST_DIR/file2.yml" "$TEST_DIR/file2.yml.backup"
}

@test "pragmatic.sh: error handling - command fails" {
    cat > "$TEST_DIR/test.yml" <<EOF
value: test ##! false
EOF

    run ./pragmatic.sh "$TEST_DIR/test.yml"

    [ "$status" -eq 2 ]
    # Original line should be preserved
    grep -q "value: test ##! false" "$TEST_DIR/test.yml"
}

@test "pragmatic.sh: error handling - nonexistent command" {
    cat > "$TEST_DIR/test.yml" <<EOF
value: test ##! nonexistent_command_xyz
EOF

    run ./pragmatic.sh "$TEST_DIR/test.yml"

    [ "$status" -eq 2 ]
    # Original line should be preserved
    grep -q "value: test ##! nonexistent_command_xyz" "$TEST_DIR/test.yml"
}

@test "pragmatic.sh: help flag" {
    run ./pragmatic.sh --help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "update-image-tag" ]]
}

@test "pragmatic.sh: no arguments shows usage" {
    run ./pragmatic.sh

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "pragmatic.sh: nonexistent file warning" {
    run ./pragmatic.sh "$TEST_DIR/nonexistent.yml"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARNING: File not found" ]]
}

@test "pragmatic.sh: multiple files with mixed results" {
    cat > "$TEST_DIR/file1.yml" <<EOF
default: registry.io/image:old ##! update_image_tag v1.0.0
EOF

    cat > "$TEST_DIR/file2.yml" <<EOF
no_markers: here
EOF

    run ./pragmatic.sh "$TEST_DIR/file1.yml" "$TEST_DIR/file2.yml"

    [ "$status" -eq 0 ]
    grep -q "registry.io/image:v1.0.0 ##! update_image_tag v1.0.0" "$TEST_DIR/file1.yml"
    grep -q "no_markers: here" "$TEST_DIR/file2.yml"
}

@test "pragmatic.sh: preserve exact comment format" {
    cat > "$TEST_DIR/test.yml" <<EOF
value: old ##! update_image_tag v1.0.0
EOF

    run ./pragmatic.sh "$TEST_DIR/test.yml"

    [ "$status" -eq 0 ]
    # Verify double hash (##!) is preserved
    grep -q "##! update_image_tag v1.0.0" "$TEST_DIR/test.yml"
}

@test "pragmatic.sh: handle multiple markers in one file" {
    cat > "$TEST_DIR/test.yml" <<EOF
image1: registry.io/app:old ##! update_image_tag v1.0.0
image2: registry.io/db:old ##! update_image_tag v2.0.0
EOF

    run ./pragmatic.sh "$TEST_DIR/test.yml"

    [ "$status" -eq 0 ]
    grep -q "image1: registry.io/app:v1.0.0 ##! update_image_tag v1.0.0" "$TEST_DIR/test.yml"
    grep -q "image2: registry.io/db:v2.0.0 ##! update_image_tag v2.0.0" "$TEST_DIR/test.yml"
}

@test "pragmatic.sh: no changes when content already matches" {
    cat > "$TEST_DIR/test.yml" <<EOF
default: registry.io/image:v1.0.0 ##! update_image_tag v1.0.0
EOF

    run ./pragmatic.sh "$TEST_DIR/test.yml"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "No change needed" ]]
}

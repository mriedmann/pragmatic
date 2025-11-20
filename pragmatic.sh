#!/bin/bash

set -euo pipefail

################################################################################
# Version Information
################################################################################

VERSION="v0.2.0" ##! echo "VERSION=\"$RELEASE_VERSION\""; echo "$1" > /dev/null

################################################################################
# Built-in Functions
################################################################################

# Built-in: update_image_tag
# Updates the image tag in a line, preserving the prefix and image name
# Args:
#   $1 - New tag to apply
#   $2 - Content before the comment
# shellcheck disable=SC2317  # Function is called from bash -c subshells
update_image_tag() {
    local new_tag="${1:-}"
    shift  # Remove first argument
    local original_line="$*"  # Everything else is the content

    if [ -z "$new_tag" ]; then
        >&2 echo "  ERROR: No tag provided"
        return 1
    fi

    # Extract prefix (everything up to last whitespace) and the image:tag at the end
    if [[ "$original_line" =~ ^(.*)[[:space:]]([^[:space:]]+)$ ]]; then
        local prefix="${BASH_REMATCH[1]} "  # Prefix with trailing space
        local image_with_tag="${BASH_REMATCH[2]}"

        # Split image:tag on the LAST colon
        if [[ "$image_with_tag" =~ ^(.+):([^:]+)$ ]]; then
            local image_without_tag="${BASH_REMATCH[1]}"
        else
            # No tag present, use the full image name
            local image_without_tag="$image_with_tag"
        fi

        # Output: prefix + image_without_tag + : + new_tag
        echo "${prefix}${image_without_tag}:${new_tag}"
        return 0
    else
        >&2 echo "  ERROR: Invalid format, expected line with image:tag at the end"
        return 1
    fi
}

# Export built-in functions so they can be called from bash -c subshells
export -f update_image_tag

################################################################################
# Main Script
################################################################################

# Parse command line options
check_mode=false
stop_after=""
files=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            echo "pragmatic version $VERSION"
            exit 0
            ;;
        -c|--check)
            check_mode=true
            shift
            ;;
        --stop-after)
            if [[ -z "${2:-}" ]] || [[ ! "${2:-}" =~ ^[0-9]+$ ]]; then
                echo "ERROR: --stop-after requires a positive number"
                exit 1
            fi
            stop_after="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS] <file1> [file2] [file3] ..."
            echo ""
            echo "Options:"
            echo "  -v, --version       Show version information"
            echo "  -c, --check         Check mode: don't modify files, exit with non-zero if changes would be made"
            echo "  --stop-after <n>    Stop processing each file after processing n ##! tags"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Exit codes:"
            echo "  0 - Success (no changes needed or changes applied successfully)"
            echo "  1 - Changes would be made (check mode only)"
            echo "  2 - Errors occurred (command not found, command failed, etc.)"
            echo ""
            echo "Built-in functions:"
            echo "  update-image-tag <tag>  - Update image tag in a line"
            echo ""
            echo "How commands are resolved:"
            echo "  - Bash looks for exported functions first, then PATH commands"
            echo "  - All commands executed via 'bash -c' with content as \$1"
            echo "  - Variables in arguments are expanded at runtime"
            echo ""
            echo "Marker examples:"
            echo "  ##! update_image_tag \$RELEASE_VERSION"
            echo "  ##! sed 's/:latest/:v1.2.3/' <<< \"\$1\""
            echo "  ##! printf '%s' \"\$1\" | sed 's/e/f/'"
            echo ""
            echo "Usage examples:"
            echo "  $0 ./templates/*.yml"
            echo "  $0 --check ./templates/*.yml"
            echo "  $0 --stop-after 1 ./pragmatic.sh"
            echo "  $0 ./templates/azure-acr-login.yml"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            files+=("$1")
            shift
            ;;
    esac
done

# Check if files were provided
if [ ${#files[@]} -eq 0 ]; then
    echo "Usage: $0 [OPTIONS] <file1> [file2] [file3] ..."
    echo "Use --help for more information"
    exit 1
fi

if [ "$check_mode" = true ]; then
    echo "Running in CHECK MODE - no changes will be made"
fi

# Track if any changes would be made across all files
any_changes=false
# Track if any errors occurred (command failures)
any_errors=false

# Process all files provided as arguments
for yaml_file in "${files[@]}"; do
    # Skip if file doesn't exist
    if [ ! -f "$yaml_file" ]; then
        echo "WARNING: File not found: $yaml_file"
        continue
    fi

    echo "Processing: $yaml_file"

    # Create a temporary file for the updated content
    temp_file=$(mktemp)
    # shellcheck disable=SC2064  # We want to expand temp_file now, not at trap time
    trap "rm -f $temp_file" EXIT

    # Track if file was modified
    modified=false
    # Track number of processed ##! tags for this file
    processed_count=0

    # Process each line - THIS REPLACES THE ENTIRE FILE LINE BY LINE
    while IFS= read -r line || [ -n "$line" ]; do
        # Check if we should stop processing (if stop_after is set and we've reached the limit)
        if [[ -n "$stop_after" ]] && [[ $processed_count -ge $stop_after ]]; then
            # Print message only once when limit is reached
            if [[ $processed_count -eq $stop_after ]]; then
                echo "  Reached limit of $stop_after processed tags, copying remaining lines as-is"
                processed_count=$((processed_count + 1))  # Increment to avoid printing message again
            fi
            # Just copy remaining lines without processing
            printf '%s\n' "$line" >> "$temp_file"
            continue
        fi

        # Check if line contains ##! comment marker (double hash!)
        if [[ "$line" =~ ^(.*)##!\ +(.+)$ ]]; then
            # Extract parts (must be done before any other operations that might clear BASH_REMATCH)
            content_before="${BASH_REMATCH[1]}"
            command="${BASH_REMATCH[2]}"

            # Increment the counter for processed tags
            processed_count=$((processed_count + 1))

            # If no $1 is found in the command, add it at the end
            # This allows markers like "##! update_image_tag $TAG" to work
            if [[ ! $command == *"\$1"* ]]; then
                command="$command \"\$1\""
            fi

            # Reconstruct the full comment marker to preserve it exactly
            comment_marker="##!"
            full_comment="${comment_marker} ${command}"

            # Trim trailing whitespace from content
            content_before="${content_before%"${content_before##*[![:space:]]}"}"

            echo "  Found marker: command='$command'"

            # Execute command via bash -c with $1 set to content_before
            # - Exported functions are available in the subshell
            # - PATH commands are resolved normally
            # - Variables in args are expanded at runtime
            set +e
            new_content=$(bash -c "$command" bash_script "$content_before")
            cmd_result=$?
            set -e

            if [ $cmd_result -eq 0 ]; then
                # Check if content actually changed
                if [ "$new_content" != "$content_before" ]; then
                    # Success - write the REPLACEMENT line with original comment preserved exactly
                    printf '%s %s\n' "$new_content" "$full_comment" >> "$temp_file"
                    modified=true
                    any_changes=true
                    if [ "$check_mode" = true ]; then
                        printf '  ! Line would be changed (check mode):\n  OLD: %s\n  NEW: %s\n' "$content_before" "$new_content"
                    else
                        echo "  ✓ Line replaced successfully"
                    fi
                else
                    # No change needed
                    if [ "$check_mode" = true ]; then
                        echo "  ✓ Line not changed (check mode)"
                    else
                        echo "  ✓ No change needed"
                    fi
                    printf '%s\n' "$line" >> "$temp_file"
                fi
            else
                # Command failed - keep original line
                echo "  ERROR: Command failed with exit code $cmd_result, keeping original line"
                any_errors=true
                printf '%s\n' "$line" >> "$temp_file"
            fi
        else
            # No marker found, keep line as-is (unchanged)
            printf '%s\n' "$line" >> "$temp_file"
        fi
    done < "$yaml_file"

    # Replace original file with the newly built content (unless in check mode)
    if [ "$check_mode" = true ]; then
        # Don't write changes in check mode
        rm -f "$temp_file"
        if [ "$modified" = true ]; then
            echo "  ! File would be modified (check mode)"
        else
            echo "  No changes needed"
        fi
    else
        # Write changes in normal mode
        mv "$temp_file" "$yaml_file"
        if [ "$modified" = true ]; then
            echo "  ✓ File updated with replacements"
        else
            echo "  No changes needed"
        fi
    fi
done

echo "Done!"

# Exit with appropriate code based on what happened
if [ "$any_errors" = true ]; then
    echo ""
    echo "ERROR: One or more commands failed. Exiting with code 2."
    exit 2
elif [ "$check_mode" = true ] && [ "$any_changes" = true ]; then
    echo ""
    echo "CHECK MODE: Changes would be made. Exiting with code 1."
    exit 1
fi

exit 0

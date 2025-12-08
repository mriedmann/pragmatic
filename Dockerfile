FROM alpine:3.23

# Install bash 5.x (Alpine's bash package provides bash 5, which is > 4.0)
# Also install other required dependencies
# hadolint ignore=DL3018
RUN apk add --no-cache \
    bash>=5.2 \
    coreutils \
    sed \
    grep

# Copy the pragmatic script
COPY pragmatic.sh /usr/local/bin/pragmatic

# Make it executable
RUN chmod +x /usr/local/bin/pragmatic

# Set working directory
WORKDIR /workspace

# Set pragmatic as the entrypoint
ENTRYPOINT ["/usr/local/bin/pragmatic"]

# Default command shows help
CMD ["--help"]

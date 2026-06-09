#!/usr/bin/env bash

# Bats test helper library
# Sourced by bats test suites

setup() {
  # Create fresh temp directory
  export TEST_TEMP_DIR
  TEST_TEMP_DIR=$(mktemp -d)

  # Initialize git repo
  git init -q "$TEST_TEMP_DIR"

  # Configure git identity
  git -C "$TEST_TEMP_DIR" config user.email "test@example.com"
  git -C "$TEST_TEMP_DIR" config user.name "Test"

  # Ensure initial branch is named 'master'
  git -C "$TEST_TEMP_DIR" commit --allow-empty -q -m init
  git -C "$TEST_TEMP_DIR" branch -M master

  # Change to temp directory
  cd "$TEST_TEMP_DIR" || return 1
}

teardown() {
  # Clean up temp directory if set and non-empty
  if [[ -n "$TEST_TEMP_DIR" ]]; then
    cd /
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# Create a PATH-stub dir, prepend it to PATH in the CURRENT shell, and expose
# its path via the global STUB_BIN. Call it directly (not via $(...)) so the
# PATH export survives — a command-substitution subshell would discard it.
make_stub_path() {
  export STUB_BIN="$TEST_TEMP_DIR/stub-bin"
  mkdir -p "$STUB_BIN"
  export PATH="$STUB_BIN:$PATH"
}
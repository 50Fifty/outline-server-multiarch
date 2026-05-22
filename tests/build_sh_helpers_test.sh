#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../build.sh
source "${ROOT_DIR}/build.sh"

TEST_TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_TMP_DIR}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    fail "${message}: expected '${expected}', got '${actual}'"
  fi
}

test_platform_to_target_arch_release_arm64() {
  PATCH_SET="release"

  assert_eq "arm64" "$(platform_to_target_arch "linux/arm64")" "release arm64 mapping"
}

test_platform_to_target_arch_master_arm64() {
  PATCH_SET="master"

  assert_eq "aarch64" "$(platform_to_target_arch "linux/arm64")" "master arm64 mapping"
}

test_split_platforms_trims_whitespace() {
  split_platforms "linux/amd64, linux/arm64"

  assert_eq "2" "${#REQUESTED_PLATFORMS[@]}" "trimmed platform count"
  assert_eq "linux/amd64" "${REQUESTED_PLATFORMS[0]}" "first trimmed platform"
  assert_eq "linux/arm64" "${REQUESTED_PLATFORMS[1]}" "second trimmed platform"
}

test_split_platforms_rejects_empty_entry() {
  local out="${TEST_TMP_DIR}/split.out"
  local err="${TEST_TMP_DIR}/split.err"

  if split_platforms "linux/amd64,,linux/arm64" >"${out}" 2>"${err}"; then
    fail "empty platform entry should fail"
  fi

  if ! grep -q "Empty platform entry" "${err}"; then
    fail "empty platform error message was not clear"
  fi
}

test_checkout_target_prefers_origin_branch() {
  local repo
  local previous_checkout_dir

  repo="$(mktemp -d "${TEST_TMP_DIR}/repo.XXXXXX")"
  previous_checkout_dir="${CHECKOUT_DIR}"
  git -C "${repo}" init -q
  git -C "${repo}" config user.email "test@example.com"
  git -C "${repo}" config user.name "Test User"
  git -C "${repo}" commit --allow-empty -q -m "initial"
  git -C "${repo}" update-ref refs/remotes/origin/master HEAD

  CHECKOUT_DIR="${repo}"
  assert_eq "origin/master" "$(checkout_target_for_checkpoint "master")" "branch checkout target"
  assert_eq "server-v1.2.3" "$(checkout_target_for_checkpoint "server-v1.2.3")" "tag checkout target"
  CHECKOUT_DIR="${previous_checkout_dir}"
}

test_no_hard_coded_build_sh_tmp_paths() {
  local fixed_tmp_pattern
  fixed_tmp_pattern='/tmp/build'"_sh_"

  if grep -q "${fixed_tmp_pattern}" "${ROOT_DIR}/build.sh"; then
    fail "build.sh should not use fixed build_sh temp paths"
  fi
}

test_source_preserves_existing_exit_trap() {
  local marker="${TEST_TMP_DIR}/source-trap-marker"

  bash -c 'set -euo pipefail; marker="$1"; script="$2"; trap "printf trap-ran > \"${marker}\"" EXIT; source "${script}"' bash "${marker}" "${ROOT_DIR}/build.sh"

  assert_eq "trap-ran" "$(cat "${marker}")" "sourcing build.sh should preserve caller EXIT trap"
}

test_append_tag_suffix_tagged_image() {
  assert_eq \
    "ghcr.io/example/shadowbox:latest-arm64" \
    "$(append_tag_suffix "ghcr.io/example/shadowbox:latest" "arm64")" \
    "tag suffix for tagged image"
}

test_append_tag_suffix_rejects_digest_image() {
  local out="${TEST_TMP_DIR}/digest.out"
  local err="${TEST_TMP_DIR}/digest.err"

  if append_tag_suffix "ghcr.io/example/shadowbox@sha256:abc123" "arm64" >"${out}" 2>"${err}"; then
    fail "digest-qualified image ref should fail"
  fi

  if ! grep -q "Digest-qualified image refs cannot be used as build output tags" "${err}"; then
    fail "digest-qualified image error message was not clear"
  fi
}

test_latest_release_tag_uses_github_token() {
  local curl_args_file
  curl_args_file="$(mktemp "${TEST_TMP_DIR}/curl_args.XXXXXX")"

  (
    curl() {
      printf '%s\n' "$@" >"${curl_args_file}"
      printf '{"tag_name":"server-v1.2.3"}\n'
    }

    jq() {
      cat >/dev/null
      printf 'server-v1.2.3\n'
    }

    GITHUB_TOKEN="test-token"

    assert_eq "server-v1.2.3" "$(latest_release_tag)" "latest release tag"
  )

  if ! grep -q "Authorization: Bearer test-token" "${curl_args_file}"; then
    fail "latest_release_tag did not pass GITHUB_TOKEN to curl"
  fi
  if declare -F curl >/dev/null || declare -F jq >/dev/null; then
    fail "latest_release_tag test should restore curl and jq shell stubs"
  fi
}

test_check_tooling_accepts_node_18() {
  (
    require_command() { :; }
    node() {
      if [[ "$1" == "-p" ]]; then
        printf '18\n'
      else
        printf 'v18.0.0\n'
      fi
    }

    check_tooling
  )
}

test_check_tooling_accepts_node_24() {
  (
    require_command() { :; }
    node() {
      if [[ "$1" == "-p" ]]; then
        printf '24\n'
      else
        printf 'v24.0.0\n'
      fi
    }

    check_tooling
  )
}

test_check_tooling_rejects_other_node_majors() {
  local out="${TEST_TMP_DIR}/check-tooling.out"
  local err="${TEST_TMP_DIR}/check-tooling.err"

  if (
    require_command() { :; }
    node() {
      if [[ "$1" == "-p" ]]; then
        printf '20\n'
      else
        printf 'v20.0.0\n'
      fi
    }

    check_tooling
  ) >"${out}" 2>"${err}"; then
    fail "check_tooling should reject unsupported Node.js majors"
  fi

  if ! grep -q "Node.js 18.x or 24.x is required by this build" "${err}"; then
    fail "unsupported Node.js error message was not clear"
  fi
}

test_reject_digest_image_ref() {
  local out="${TEST_TMP_DIR}/reject-digest.out"
  local err="${TEST_TMP_DIR}/reject-digest.err"

  if reject_digest_image_ref "ghcr.io/example/shadowbox@sha256:abc123" >"${out}" 2>"${err}"; then
    fail "digest-qualified image ref should be rejected"
  fi

  if ! grep -q "Digest-qualified image refs cannot be used as build output tags" "${err}"; then
    fail "digest rejection error message was not clear"
  fi
}

test_main_rejects_digest_before_tooling() {
  local out="${TEST_TMP_DIR}/main-digest.out"
  local err="${TEST_TMP_DIR}/main-digest.err"

  if (
    check_tooling() {
      printf 'check_tooling called\n' >&2
      return 2
    }

    main "linux/amd64" "ghcr.io/example/shadowbox@sha256:abc123" "latest"
  ) >"${out}" 2>"${err}"; then
    fail "main should reject digest-qualified image refs"
  fi

  if grep -q "check_tooling called" "${err}"; then
    fail "main called check_tooling before rejecting the digest-qualified image ref"
  fi

  if ! grep -q "Digest-qualified image refs cannot be used as build output tags" "${err}"; then
    fail "main digest rejection error message was not clear"
  fi
}

test_apply_patches_rejects_missing_patch_dir() {
  local out="${TEST_TMP_DIR}/missing-patch-dir.out"
  local err="${TEST_TMP_DIR}/missing-patch-dir.err"

  if (
    PATCH_SET="missing-test-patch-set"
    apply_patches
  ) >"${out}" 2>"${err}"; then
    fail "missing patch directory should fail"
  fi

  if ! grep -q "Patch directory not found" "${err}"; then
    fail "missing patch directory error message was not clear"
  fi
}

test_platform_to_target_arch_release_arm64
test_platform_to_target_arch_master_arm64
test_split_platforms_trims_whitespace
test_split_platforms_rejects_empty_entry
test_checkout_target_prefers_origin_branch
test_no_hard_coded_build_sh_tmp_paths
test_source_preserves_existing_exit_trap
test_append_tag_suffix_tagged_image
test_append_tag_suffix_rejects_digest_image
test_latest_release_tag_uses_github_token
test_check_tooling_accepts_node_18
test_check_tooling_accepts_node_24
test_check_tooling_rejects_other_node_majors
test_reject_digest_image_ref
test_main_rejects_digest_before_tooling
test_apply_patches_rejects_missing_patch_dir

printf 'All build.sh helper tests passed.\n'

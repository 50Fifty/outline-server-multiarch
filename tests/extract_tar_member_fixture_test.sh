#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_DIR="$(mktemp -d)"
trap 'chmod -R u+w "${TEST_TMP_DIR}" 2>/dev/null || true; rm -rf "${TEST_TMP_DIR}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

sha256_file() {
  local file="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 -r "${file}" | awk '{print $1}'
  else
    fail "No SHA-256 command found"
  fi
}

extract_node_script() {
  local patch="$1"
  local out="$2"

  sed -n '/^+import /,/^diff --git a\/third_party\/Taskfile.yml/p' "${patch}" \
    | sed '$d; s/^+//' >"${out}"
}

assert_git_applied_node_script_parses() {
  local patch="$1"
  local apply_dir
  local script

  apply_dir="$(mktemp -d "${TEST_TMP_DIR}/git-apply.XXXXXX")"
  script="${apply_dir}/src/build/extract_tar_member.mjs"

  git -C "${apply_dir}" init -q
  git -C "${apply_dir}" apply --include=src/build/extract_tar_member.mjs "${patch}"
  node --check "${script}" >/dev/null
}

run_fixture_for_patch() {
  local patch="$1"
  local case_dir
  local script
  local archive
  local out
  local expected_sha

  case_dir="$(mktemp -d "${TEST_TMP_DIR}/extract.XXXXXX")"
  script="${case_dir}/extract_tar_member.mjs"
  archive="${case_dir}/fixture.tar.gz"
  out="${case_dir}/out/prometheus"

  extract_node_script "${patch}" "${script}"
  assert_git_applied_node_script_parses "${patch}"

  if grep -Eq 'readFile|gunzipSync' "${script}"; then
    fail "${patch} still uses whole-archive read/decompression"
  fi
  if grep -Fq 'Buffer.concat([buffer, chunk])' "${script}"; then
    fail "${patch} still appends gunzip chunks with repeated Buffer.concat"
  fi
  if ! grep -Fq "writer.on('error'" "${script}"; then
    fail "${patch} does not install an explicit writer error handler"
  fi
  if ! grep -Fq "source.on('error'" "${script}"; then
    fail "${patch} does not install an explicit source error handler"
  fi
  if grep -Fq "waitForWriterEvent(current.writer, 'finish'" "${script}"; then
    fail "${patch} still treats writer finish as final completion"
  fi
  if ! grep -Fq "waitForWriterEvent(current.writer, 'close'" "${script}"; then
    fail "${patch} does not wait for writer close before publishing output"
  fi

  mkdir -p "${case_dir}/prometheus-1.0.0.linux-amd64"
  printf 'fixture-prometheus\n' >"${case_dir}/prometheus-1.0.0.linux-amd64/prometheus"
  tar -czf "${archive}" -C "${case_dir}" "prometheus-1.0.0.linux-amd64/prometheus"
  expected_sha="$(sha256_file "${archive}")"

  node "${script}" "${archive}" "${out}" "/prometheus" "${expected_sha}"
  if [[ "$(cat "${out}")" != "fixture-prometheus" ]]; then
    fail "${patch} did not extract the expected member"
  fi

  if node "${script}" "${archive}" "${case_dir}/missing" "/not-present" "${expected_sha}" >/dev/null 2>"${case_dir}/missing.err"; then
    fail "${patch} should fail when the member is missing"
  fi
  if ! grep -q "No archive member ends with /not-present" "${case_dir}/missing.err"; then
    fail "${patch} missing-member error was not clear"
  fi

  if node "${script}" "${archive}" "${case_dir}/bad-sha" "/prometheus" "0000" >/dev/null 2>"${case_dir}/sha.err"; then
    fail "${patch} should fail on SHA mismatch"
  fi
  if ! grep -q "Expected SHA-256 0000" "${case_dir}/sha.err"; then
    fail "${patch} SHA mismatch error was not clear"
  fi

  local readonly_dir="${case_dir}/readonly-output"
  mkdir -p "${readonly_dir}"
  chmod 500 "${readonly_dir}"
  if node "${script}" "${archive}" "${readonly_dir}/prometheus" "/prometheus" "${expected_sha}" >/dev/null 2>"${case_dir}/writer.err"; then
    fail "${patch} should fail when the output stream errors"
  fi
  chmod 700 "${readonly_dir}"
  if compgen -G "${readonly_dir}/prometheus.tmp-*" >/dev/null; then
    fail "${patch} left a temp output behind after writer failure"
  fi

  if node "${script}" "${case_dir}/missing-archive.tar.gz" "${case_dir}/missing-source/prometheus" "/prometheus" "0000" >/dev/null 2>"${case_dir}/source.err"; then
    fail "${patch} should fail when the archive cannot be read"
  fi
  if grep -q "Unhandled 'error' event" "${case_dir}/source.err"; then
    fail "${patch} surfaced source read failure as an unhandled error"
  fi
  if compgen -G "${case_dir}/missing-source/prometheus.tmp-*" >/dev/null; then
    fail "${patch} left a temp output behind after source read failure"
  fi
}

run_fixture_for_patch "${ROOT_DIR}/patches/release/0002-extract_prometheus_with_node.patch"
run_fixture_for_patch "${ROOT_DIR}/patches/master/0002-extract_prometheus_with_node.patch"

printf 'All extract_tar_member fixture tests passed.\n'

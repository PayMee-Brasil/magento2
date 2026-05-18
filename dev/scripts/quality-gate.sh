#!/usr/bin/env sh
set -eu

REPORT_DIR="dev/quality/reports"
SUMMARY_FILE="${REPORT_DIR}/summary.md"
PHP_LINT_REPORT="${REPORT_DIR}/php-lint.txt"

mkdir -p "${REPORT_DIR}"

log() {
  printf '[quality-gate] %s\n' "$1"
}

append_summary() {
  printf '%s\n' "$1" >> "${SUMMARY_FILE}"
}

configure_git_safe_directory() {
  if command -v git >/dev/null 2>&1; then
    git config --global --add safe.directory "${GITHUB_WORKSPACE:-$(pwd)}" 2>/dev/null || true
    git config --global --add safe.directory "$(pwd)" 2>/dev/null || true
  fi
}

: > "${SUMMARY_FILE}"
: > "${PHP_LINT_REPORT}"

append_summary '# Quality Gate'
append_summary ''
append_summary '| Check | Result |'
append_summary '| --- | --- |'

configure_git_safe_directory

log 'Running composer validate'
if composer validate --no-interaction; then
  append_summary '| Composer validate | Passed |'
else
  append_summary '| Composer validate | Failed |'
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    cat "${SUMMARY_FILE}" >> "${GITHUB_STEP_SUMMARY}"
  fi
  exit 1
fi

log 'Running PHP syntax checks'
if ! git ls-files >/dev/null 2>&1; then
  append_summary '| Git files listing | Failed: unable to list tracked files |'
  log 'Unable to list Git tracked files. Check safe.directory or checkout state.'
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    cat "${SUMMARY_FILE}" >> "${GITHUB_STEP_SUMMARY}"
  fi
  exit 1
fi

php_files="$(git ls-files '*.php')"

if [ -z "${php_files}" ]; then
  append_summary '| PHP syntax | Skipped: no PHP files found |'
else
  lint_failed=0
  for file in ${php_files}; do
    if ! php -l "${file}" >> "${PHP_LINT_REPORT}" 2>&1; then
      lint_failed=1
    fi
  done

  if [ "${lint_failed}" -eq 0 ]; then
    append_summary '| PHP syntax | Passed |'
  else
    append_summary "| PHP syntax | Failed: see ${PHP_LINT_REPORT} |"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      cat "${SUMMARY_FILE}" >> "${GITHUB_STEP_SUMMARY}"
    fi
    exit 1
  fi
fi

append_summary ''
append_summary "Reports directory: \`${REPORT_DIR}\`"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "${SUMMARY_FILE}" >> "${GITHUB_STEP_SUMMARY}"
fi

log "Quality gate passed. Summary: ${SUMMARY_FILE}"

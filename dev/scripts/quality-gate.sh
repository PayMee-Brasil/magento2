#!/usr/bin/env sh
set -eu

REPORT_DIR="dev/quality/reports"
SUMMARY_FILE="${REPORT_DIR}/summary.md"
PHP_LINT_REPORT="${REPORT_DIR}/php-lint.txt"
PHPSTAN_REPORT_DIR="${REPORT_DIR}/phpstan"
PHPSTAN_SUMMARY_REPORT="${PHPSTAN_REPORT_DIR}/phpstan-summary.txt"
PHPSTAN_MARKDOWN_REPORT="${PHPSTAN_REPORT_DIR}/phpstan-summary.md"
PHPSTAN_TEXT_REPORT="${PHPSTAN_REPORT_DIR}/phpstan.txt"
PHPSTAN_JSON_REPORT="${PHPSTAN_REPORT_DIR}/phpstan.json"
PHPSTAN_VERSION="2.1.55"
PHPSTAN_SHA256="5e2cd0da9dd9f0de64c97b06787efc5e6cfd3a20b1622854d9b1c4cf195d1c72"
PHPSTAN_CACHE_DIR="dev/quality/.cache/phpstan"
PHPSTAN_PHAR="${PHPSTAN_CACHE_DIR}/phpstan-${PHPSTAN_VERSION}.phar"
PHPSTAN_CONFIG="dev/quality/phpstan.neon"
PHPSTAN_ENFORCE="${PHPSTAN_ENFORCE:-0}"

mkdir -p "${REPORT_DIR}"
mkdir -p "${PHPSTAN_REPORT_DIR}"

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

begin_group() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::group::%s\n' "$1"
  fi
}

end_group() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::endgroup::\n'
  fi
}

ensure_phpstan() {
  if [ -x "vendor/bin/phpstan" ]; then
    PHPSTAN_COMMAND='vendor/bin/phpstan'
    return
  fi

  if command -v phpstan >/dev/null 2>&1; then
    PHPSTAN_COMMAND='phpstan'
    return
  fi

  mkdir -p "${PHPSTAN_CACHE_DIR}"

  if [ ! -f "${PHPSTAN_PHAR}" ]; then
    log "Downloading PHPStan ${PHPSTAN_VERSION}"
    php -r "copy('https://github.com/phpstan/phpstan/releases/download/${PHPSTAN_VERSION}/phpstan.phar', '${PHPSTAN_PHAR}');"
  fi

  actual_hash="$(php -r "echo hash_file('sha256', '${PHPSTAN_PHAR}');")"
  if [ "${actual_hash}" != "${PHPSTAN_SHA256}" ]; then
    rm -f "${PHPSTAN_PHAR}"
    log 'PHPStan PHAR checksum mismatch.'
    exit 1
  fi

  PHPSTAN_COMMAND="php ${PHPSTAN_PHAR}"
}

run_phpstan() {
  # shellcheck disable=SC2086
  ${PHPSTAN_COMMAND} analyse --configuration="${PHPSTAN_CONFIG}" "$@"
}

print_report_sample() {
  php -r '
    $file = $argv[1];
    $limit = (int) $argv[2];
    $lines = is_file($file) ? file($file) : [];
    echo implode("", array_slice($lines, 0, $limit));
    if (count($lines) > $limit) {
      echo "\n[quality-gate] Output truncated in job log. See full report artifact: {$file}\n";
    }
  ' "$1" "$2"
}

summarize_phpstan_json() {
  php -r '
    $file = $argv[1];
    $data = json_decode(is_file($file) ? file_get_contents($file) : "", true);
    if (!is_array($data)) {
      echo "PHPStan JSON summary unavailable. See raw report.\n";
      exit(0);
    }

    $totalErrors = (int) ($data["totals"]["errors"] ?? 0);
    $fileErrors = (int) ($data["totals"]["file_errors"] ?? 0);
    $files = $data["files"] ?? [];

    echo "PHPStan summary\n";
    echo "===============\n";
    echo "General errors: {$totalErrors}\n";
    echo "File errors: {$fileErrors}\n";
    echo "Files with findings: " . count($files) . "\n\n";

    if (count($files) > 0) {
      echo "Top files by findings:\n";
      uasort($files, static fn($a, $b) => ((int) ($b["errors"] ?? 0)) <=> ((int) ($a["errors"] ?? 0)));
      $shown = 0;
      foreach ($files as $path => $info) {
        echo "- {$path}: " . ((int) ($info["errors"] ?? 0)) . "\n";
        $shown++;
        if ($shown >= 10) {
          break;
        }
      }
    }
  ' "$PHPSTAN_JSON_REPORT" > "$PHPSTAN_SUMMARY_REPORT" 2>/dev/null || true
}

write_phpstan_markdown_report() {
  php -r '
    $jsonFile = $argv[1];
    $outputFile = $argv[2];
    $mode = $argv[3];
    $data = json_decode(is_file($jsonFile) ? file_get_contents($jsonFile) : "", true);

    $lines = [];
    $lines[] = "## PHPStan Summary";
    $lines[] = "";

    if (!is_array($data)) {
      $lines[] = "PHPStan JSON summary is unavailable. See the raw PHPStan reports in the artifact.";
      file_put_contents($outputFile, implode("\n", $lines) . "\n");
      exit(0);
    }

    $totalErrors = (int) ($data["totals"]["errors"] ?? 0);
    $fileErrors = (int) ($data["totals"]["file_errors"] ?? 0);
    $files = $data["files"] ?? [];
    $filesWithFindings = count($files);

    $lines[] = "| Metric | Value |";
    $lines[] = "| --- | ---: |";
    $lines[] = "| General errors | {$totalErrors} |";
    $lines[] = "| File findings | {$fileErrors} |";
    $lines[] = "| Files with findings | {$filesWithFindings} |";
    $lines[] = "| Mode | {$mode} |";
    $lines[] = "";

    if ($filesWithFindings > 0) {
      $lines[] = "### Top Files By Findings";
      $lines[] = "";
      $lines[] = "| File | Findings |";
      $lines[] = "| --- | ---: |";
      uasort($files, static fn($a, $b) => ((int) ($b["errors"] ?? 0)) <=> ((int) ($a["errors"] ?? 0)));
      $shown = 0;
      foreach ($files as $path => $info) {
        $path = preg_replace("#^/app/#", "", $path);
        $lines[] = "| `{$path}` | " . ((int) ($info["errors"] ?? 0)) . " |";
        $shown++;
        if ($shown >= 10) {
          break;
        }
      }
      $lines[] = "";
    }

    $lines[] = "> PHPStan is currently advisory. Most current findings are expected while Magento framework dependencies are not installed in the CI container.";
    $lines[] = "> Download the `quality-gate-report` artifact for full text and JSON details.";
    file_put_contents($outputFile, implode("\n", $lines) . "\n");
  ' "$1" "$2" "$3"
}

: > "${SUMMARY_FILE}"
: > "${PHP_LINT_REPORT}"
: > "${PHPSTAN_SUMMARY_REPORT}"
: > "${PHPSTAN_MARKDOWN_REPORT}"
: > "${PHPSTAN_TEXT_REPORT}"
: > "${PHPSTAN_JSON_REPORT}"

append_summary '# Quality Gate'
append_summary ''
append_summary '## Result'
append_summary ''
append_summary '| Check | Status | Notes |'
append_summary '| --- | --- | --- |'

configure_git_safe_directory

begin_group 'Composer validate'
log 'Running composer validate'
if composer validate --no-interaction; then
  append_summary '| Composer validate | Passed | `composer.json` is valid; Composer may still emit warnings. |'
else
  append_summary '| Composer validate | Failed | See job log for Composer output. |'
  exit 1
fi
end_group

begin_group 'PHP syntax'
log 'Running PHP syntax checks'
if ! git ls-files >/dev/null 2>&1; then
  append_summary '| Git files listing | Failed | Unable to list tracked files. Check `safe.directory` or checkout state. |'
  log 'Unable to list Git tracked files. Check safe.directory or checkout state.'
  exit 1
fi

php_files="$(git ls-files '*.php')"

if [ -z "${php_files}" ]; then
  append_summary '| PHP syntax | Skipped | No PHP files found. |'
else
  lint_failed=0
  for file in ${php_files}; do
    if ! php -l "${file}" >> "${PHP_LINT_REPORT}" 2>&1; then
      lint_failed=1
    fi
  done

  if [ "${lint_failed}" -eq 0 ]; then
    append_summary '| PHP syntax | Passed | All tracked PHP files parsed successfully. |'
  else
    append_summary "| PHP syntax | Failed | See \`${PHP_LINT_REPORT}\`. |"
    exit 1
  fi
fi
end_group

begin_group 'PHPStan static analysis'
log 'Running PHPStan static analysis'
ensure_phpstan

set +e
run_phpstan --no-progress --error-format=table > "${PHPSTAN_TEXT_REPORT}" 2>&1
phpstan_status=$?
set -e

set +e
run_phpstan --no-progress --error-format=json > "${PHPSTAN_JSON_REPORT}" 2>&1
phpstan_json_status=$?
set -e

summarize_phpstan_json
cat "${PHPSTAN_SUMMARY_REPORT}"

log 'PHPStan report sample'
print_report_sample "${PHPSTAN_TEXT_REPORT}" 80

phpstan_file_errors="$(php -r '
  $data = json_decode(is_file($argv[1]) ? file_get_contents($argv[1]) : "", true);
  echo is_array($data) ? (int) ($data["totals"]["file_errors"] ?? 0) : "unknown";
' "${PHPSTAN_JSON_REPORT}" 2>/dev/null || printf 'unknown')"

if [ "${phpstan_status}" -eq 0 ]; then
  phpstan_mode='Passing'
  append_summary '| PHPStan | Passed | Static analysis completed without findings. |'
else
  if [ "${PHPSTAN_ENFORCE}" = "1" ]; then
    phpstan_mode='Enforced'
    append_summary "| PHPStan | Failed | ${phpstan_file_errors} file findings. See \`${PHPSTAN_TEXT_REPORT}\`. |"
  else
    phpstan_mode='Advisory'
    append_summary "| PHPStan | Advisory | ${phpstan_file_errors} file findings. See \`${PHPSTAN_TEXT_REPORT}\`. |"
  fi
fi

if [ "${phpstan_json_status}" -ne 0 ]; then
  log "PHPStan JSON report command exited with status ${phpstan_json_status}. See ${PHPSTAN_JSON_REPORT}."
fi
end_group

write_phpstan_markdown_report "${PHPSTAN_JSON_REPORT}" "${PHPSTAN_MARKDOWN_REPORT}" "${phpstan_mode}"
cat "${PHPSTAN_MARKDOWN_REPORT}" >> "${SUMMARY_FILE}"

append_summary ''
append_summary '## Reports'
append_summary ''
append_summary "- PHP lint: \`${PHP_LINT_REPORT}\`"
append_summary "- PHPStan summary: \`${PHPSTAN_SUMMARY_REPORT}\`"
append_summary "- PHPStan markdown summary: \`${PHPSTAN_MARKDOWN_REPORT}\`"
append_summary "- PHPStan text: \`${PHPSTAN_TEXT_REPORT}\`"
append_summary "- PHPStan JSON: \`${PHPSTAN_JSON_REPORT}\`"
append_summary "Reports directory: \`${REPORT_DIR}\`"

if [ "${phpstan_status}" -ne 0 ] && [ "${PHPSTAN_ENFORCE}" = "1" ]; then
  exit 1
fi

log 'Summary'
log 'Composer validate: passed'
log 'PHP syntax: passed'
log "PHPStan: ${phpstan_mode}, ${phpstan_file_errors} file findings"
log 'Full reports are uploaded as the quality-gate-report artifact in GitHub Actions.'
log "Quality gate passed. Summary: ${SUMMARY_FILE}"

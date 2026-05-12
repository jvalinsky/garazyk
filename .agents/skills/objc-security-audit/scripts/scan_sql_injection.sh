#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-sql-injection-deep-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

scan_path="$root_dir"
if [[ -d "$root_dir/Garazyk/Sources" ]]; then
  scan_path="$root_dir/Garazyk/Sources"
fi

mkdir -p "$out_dir"

format_sql_hits="$out_dir/format_sql_hits.txt"
concat_sql_hits="$out_dir/concat_sql_hits.txt"
exec_hits="$out_dir/exec_hits.txt"
prepare_hits="$out_dir/prepare_hits.txt"
bind_hits="$out_dir/bind_hits.txt"
dynamic_table_hits="$out_dir/dynamic_table_hits.txt"
where_format_hits="$out_dir/where_format_hits.txt"

rg -n --glob '*.{m,mm,h}' \
  -e 'stringWithFormat:.*SELECT' \
  -e 'stringWithFormat:.*INSERT' \
  -e 'stringWithFormat:.*UPDATE' \
  -e 'stringWithFormat:.*DELETE' \
  -e 'stringWithFormat:.*CREATE' \
  -e 'stringWithFormat:.*DROP' \
  -e 'stringWithFormat:.*ALTER' \
  "$scan_path" >"$format_sql_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'stringByAppendingString.*SELECT' \
  -e 'stringByAppendingString.*INSERT' \
  -e 'stringByAppendingString.*WHERE' \
  -e 'strcat.*SELECT' \
  "$scan_path" >"$concat_sql_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'sqlite3_exec\s*\(' \
  -e 'executeQuery:' \
  -e 'executeUnsafeRawQuery:' \
  -e 'executeRawSQL:' \
  -e 'executeUnsafeRawSQL:' \
  -e 'executeUpdate:' \
  -e '\[.*execute' \
  "$scan_path" >"$exec_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'sqlite3_prepare(_v2)?\s*\(' \
  "$scan_path" >"$prepare_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'sqlite3_bind_' \
  -e 'sqlite3_bind_text' \
  -e 'sqlite3_bind_int' \
  -e 'sqlite3_bind_blob' \
  "$scan_path" >"$bind_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'CREATE TABLE.*%@' \
  -e 'ALTER TABLE.*%@' \
  -e 'DROP TABLE.*%@' \
  -e 'FROM.*%@' \
  -e 'INTO.*%@' \
  "$scan_path" >"$dynamic_table_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e "WHERE.*=.*'%@'" \
  -e 'WHERE.*=.*"%@"' \
  -e "WHERE.*LIKE.*'%@'" \
  -e 'WHERE.*IN.*%@' \
  "$scan_path" >"$where_format_hits" || true

safe_param_hits="$out_dir/safe_param_hits.txt"
rg -n --glob '*.{m,mm,h}' \
  -e 'WHERE.*\?' \
  -e 'WHERE.*:\w+' \
  "$scan_path" >"$safe_param_hits" || true

cut -d: -f1 "$format_sql_hits" | sort -u >"$out_dir/format_sql_files.txt"
cut -d: -f1 "$exec_hits" | sort -u >"$out_dir/exec_files.txt"
cut -d: -f1 "$prepare_hits" | sort -u >"$out_dir/prepare_files.txt"

comm -12 "$out_dir/format_sql_files.txt" "$out_dir/exec_files.txt" >"$out_dir/format_and_exec.txt"

summary="$out_dir/summary.md"
{
  echo "# Objective-C SQL Injection Deep Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Scan path: $scan_path"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- SQL with string formatting: $(wc -l < "$format_sql_hits" | tr -d ' ')"
  echo "- SQL with string concatenation: $(wc -l < "$concat_sql_hits" | tr -d ' ')"
  echo "- SQL execution points: $(wc -l < "$exec_hits" | tr -d ' ')"
  echo "- Prepared statement sites: $(wc -l < "$prepare_hits" | tr -d ' ')"
  echo "- Parameter binding sites: $(wc -l < "$bind_hits" | tr -d ' ')"
  echo "- Dynamic table/column names: $(wc -l < "$dynamic_table_hits" | tr -d ' ')"
  echo "- WHERE clause with format: $(wc -l < "$where_format_hits" | tr -d ' ')"
  echo "- Safe parameterized queries: $(wc -l < "$safe_param_hits" | tr -d ' ')"
  echo
  echo "## High priority (format + exec in same file)"
  if [[ -s "$out_dir/format_and_exec.txt" ]]; then
    sed 's/^/- /' "$out_dir/format_and_exec.txt"
  else
    echo "- none detected"
  fi
  echo
  echo "## Detailed findings"
  echo
  echo "### SQL with string formatting"
  if [[ -s "$format_sql_hits" ]]; then
    head -20 "$format_sql_hits" | sed 's/^/  /'
    if [[ $(wc -l < "$format_sql_hits") -gt 20 ]]; then
      echo "  ... and $(( $(wc -l < "$format_sql_hits") - 20 )) more"
    fi
  else
    echo "  none"
  fi
  echo
  echo "### Dynamic table/column names"
  if [[ -s "$dynamic_table_hits" ]]; then
    head -10 "$dynamic_table_hits" | sed 's/^/  /'
  else
    echo "  none"
  fi
  echo
  echo "### WHERE clause with format strings"
  if [[ -s "$where_format_hits" ]]; then
    head -15 "$where_format_hits" | sed 's/^/  /'
  else
    echo "  none"
  fi
  echo
  echo "## Notes"
  echo "- Format strings in SQL context require manual review."
  echo "- Check if format arguments are user-controlled."
  echo "- Prepared statements with bind are the safe pattern."
  echo "- Dynamic table names need whitelisting, not escaping."
} >"$summary"

echo "wrote $summary"

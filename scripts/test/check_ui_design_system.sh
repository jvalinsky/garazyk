#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || (cd "${script_dir}/../.." && pwd))"

html_files=(
  "${repo_root}/Garazyk/Sources/App/MSTViewer/Assets/index.html"
  "${repo_root}/Garazyk/Sources/App/OAuthDemo/Assets/index.html"
  "${repo_root}/Garazyk/Sources/Auth/Assets/authorize.html"
  "${repo_root}/Garazyk/Sources/PLC/Assets/index.html"
)

css_files=(
  "${repo_root}/Garazyk/Sources/PLC/Assets/css/plc.css"
  "${repo_root}/Garazyk/Sources/App/MSTViewer/Assets/css/mst-viewer.css"
  "${repo_root}/Garazyk/Sources/App/OAuthDemo/Assets/css/oauth-demo.css"
)

js_files=(
  "${repo_root}/Garazyk/Sources/PLC/Assets/js"
  "${repo_root}/Garazyk/Sources/App/MSTViewer/Assets/js"
)

failed=0

echo "[check-ui-design-system] Verifying production templates..."
for file in "${html_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "ERROR: Missing file: $file"
    failed=1
    continue
  fi

  if rg -n "<style\\b" "$file" >/dev/null; then
    echo "ERROR: Inline <style> block detected in $file"
    failed=1
  fi

  if rg -n "style\\s*=" "$file" >/dev/null; then
    echo "ERROR: Inline style= attribute detected in $file"
    failed=1
  fi

done

echo "[check-ui-design-system] Verifying JS templates avoid inline style attributes..."
existing_js_files=()
for path in "${js_files[@]}"; do
  if [[ -e "$path" ]]; then
    existing_js_files+=("$path")
  else
    echo "ERROR: Missing JS asset path: $path"
    failed=1
  fi
done

if [[ "${#existing_js_files[@]}" -gt 0 ]] && rg -n "style\\s*=" "${existing_js_files[@]}" --glob '!**/d3.js' >/dev/null; then
  echo "ERROR: Inline style= attribute detected in UI JS templates"
  rg -n "style\\s*=" "${existing_js_files[@]}" --glob '!**/d3.js' || true
  failed=1
fi

if [[ "${#existing_js_files[@]}" -gt 0 ]] && rg -n "style\\.cssText" "${existing_js_files[@]}" --glob '!**/d3.js' >/dev/null; then
  echo "ERROR: style.cssText usage detected in UI JS"
  rg -n "style\\.cssText" "${existing_js_files[@]}" --glob '!**/d3.js' || true
  failed=1
fi

echo "[check-ui-design-system] Verifying shared DesignSystem imports..."
for file in "${html_files[@]}"; do
  if ! rg -n "shared/system\\.css" "$file" >/dev/null; then
    echo "ERROR: Missing shared/system.css import in $file"
    failed=1
  fi
done

echo "[check-ui-design-system] Verifying no legacy style.css dependencies..."
if rg -n "href=.*style\\.css|/css/style\\.css|css/style\\.css" \
  "${repo_root}/Garazyk/Sources/PLC/Assets/index.html" \
  "${repo_root}/Garazyk/Sources/App/MSTViewer/Assets/index.html" >/dev/null; then
  echo "ERROR: Legacy style.css dependency detected in UI entry templates"
  rg -n "href=.*style\\.css|/css/style\\.css|css/style\\.css" \
    "${repo_root}/Garazyk/Sources/PLC/Assets/index.html" \
    "${repo_root}/Garazyk/Sources/App/MSTViewer/Assets/index.html" || true
  failed=1
fi

echo "[check-ui-design-system] Verifying legacy asset packs are not referenced..."
if rg -n "/css/(fonts|icon)/|css/(fonts|icon)/" \
  "${repo_root}/Garazyk/Sources/PLC/Assets" >/dev/null; then
  echo "ERROR: Legacy font/icon asset reference detected in Explore/PLC assets"
  rg -n "/css/(fonts|icon)/|css/(fonts|icon)/" \
    "${repo_root}/Garazyk/Sources/PLC/Assets" || true
  failed=1
fi

echo "[check-ui-design-system] Verifying local CSS token usage..."
for file in "${css_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "ERROR: Missing CSS file: $file"
    failed=1
    continue
  fi

  if rg -n "(#[0-9A-Fa-f]{3,8}\\b|rgba?\\(|hsla?\\()" "$file" >/dev/null; then
    echo "ERROR: Hard-coded color literal found in $file (use shared tokens)"
    rg -n "(#[0-9A-Fa-f]{3,8}\\b|rgba?\\(|hsla?\\()" "$file" || true
    failed=1
  fi

  if rg -n "\\b(margin|padding|gap)\\s*:\\s*[^;]*\\b\\d+px\\b" "$file" >/dev/null; then
    echo "ERROR: Hard-coded spacing literal found in $file (use spacing tokens)"
    rg -n "\\b(margin|padding|gap)\\s*:\\s*[^;]*\\b\\d+px\\b" "$file" || true
    failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  echo "[check-ui-design-system] FAILED"
  exit 1
fi

echo "[check-ui-design-system] PASS"

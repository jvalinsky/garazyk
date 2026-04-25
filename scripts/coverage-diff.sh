#!/bin/bash
# Coverage Diff - Compare baseline vs mutator coverage
# Usage: ./coverage-diff.sh <corpus-dir> <baseline-fuzzer> <mutator-fuzzer> [runs]

set -e

CORPUS_DIR="${1:-fuzzing/corpus/auth}"
BASELINE="${2:-build/fuzzing/fuzz_jwt}"
MUTATOR="${3:-build/fuzzing/fuzz_jwt_struct}"
RUNS="${4:-10000}"
OUTPUT="${5:-fuzzing/coverage-diff}"

mkdir -p "$OUTPUT"

echo "=== Coverage Diff ==="
echo "Corpus:    $CORPUS_DIR"
echo "Baseline: $BASELINE"
echo "Mutator:  $MUTATOR"
echo "Runs:     $RUNS"
echo ""

# Run baseline
echo "Running baseline..."
"$BASELINE" "$CORPUS_DIR" -runs="$RUNS" -print_final_stats 2>&1 | tee "$OUTPUT/baseline.log"
BASELINE_EDGES=$(grep -o 'edge.*cov' "$OUTPUT/baseline.log" | awk '{print $NF}' || echo 0)
echo "Baseline edges: $BASELINE_EDGES"

# Run mutator
echo ""
echo "Running mutator..."
"$MUTATOR" "$CORPUS_DIR" -runs="$RUNS" -print_final_stats 2>&1 | tee "$OUTPUT/mutator.log"
MUTATOR_EDGES=$(grep -o 'edge.*cov' "$OUTPUT/mutator.log" | awk '{print $NF}' || echo 0)
echo "Mutator edges: $MUTATOR_EDGES"

# Calculate diff
BASELINE_NUM=${BASELINE_EDGES:-0}
MUTATOR_NUM=${MUTATOR_EDGES:-0}

if [ "$MUTATOR_NUM" -gt "$BASELINE_NUM" ]; then
    DIFF=$((MUTATOR_NUM - BASELINE_NUM))
    DIFF_PCT=$(echo "scale=1; ($DIFF * 100) / $BASELINE_NUM" | bc 2>/dev/null || echo 0)
    STATUS="✅ Mutator improved coverage by +$DIFF ($DIFF_PCT%)"
elif [ "$MUTATOR_NUM" -lt "$BASELINE_NUM" ]; then
    DIFF=$((BASELINE_NUM - MUTATOR_NUM))
    DIFF_PCT=$(echo "scale=1; ($DIFF * 100) / $BASELINE_NUM" | bc 2>/dev/null || echo 0)
    STATUS="⚠️  Baseline better by -$DIFF ($DIFF_PCT%)"
else
    STATUS="➖ Equal coverage"
fi

# Generate HTML report
REPORT="$OUTPUT/report.html"

cat > "$REPORT" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Coverage Diff Report</title>
  <style>
    :root {
      --bg: #0d1117;
      --bg-secondary: #161b22;
      --border: #30363d;
      --text: #c9d1d9;
      --text-secondary: #8b949e;
      --green: #238636;
      --red: #f85149;
      --blue: #1f6feb;
      --purple: #a371f7;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.5;
      padding: 20px;
    }
    .container { max-width: 900px; margin: 0 auto; }
    h1 { margin-bottom: 10px; }
    .subtitle { color: var(--text-secondary); margin-bottom: 30px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 30px; }
    .card {
      background: var(--bg-secondary);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 20px;
    }
    .stat-value { font-size: 32px; font-weight: 600; }
    .stat-label { font-size: 12px; color: var(--text-secondary); text-transform: uppercase; }
    .status { padding: 10px 20px; border-radius: 8px; font-weight: 600; margin-bottom: 30px; }
    .status.improved { background: rgba(35, 134, 54, 0.2); color: var(--green); border: 1px solid var(--green); }
    .status.regressed { background: rgba(248, 81, 73, 0.2); color: var(--red); border: 1px solid var(--red); }
    .status.equal { background: rgba(139, 148, 158, 0.2); color: var(--text-secondary); border: 1px solid var(--text-secondary); }
    .bar-container { margin-bottom: 20px; }
    .bar-label { display: flex; justify-content: space-between; margin-bottom: 5px; }
    .bar-bg {
      height: 24px;
      background: var(--border);
      border-radius: 4px;
      overflow: hidden;
      display: flex;
    }
    .bar-fill {
      height: 100%;
      border-radius: 4px;
      transition: width 0.5s ease;
    }
    .bar-baseline { background: var(--text-secondary); }
    .bar-mutator { background: var(--blue); }
    .info { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 8px; padding: 20px; }
    .info h3 { margin-bottom: 10px; }
    .info p { color: var(--text-secondary); font-size: 14px; }
    footer { margin-top: 40px; text-align: center; color: var(--text-secondary); font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Coverage Diff Report</h1>
    <p class="subtitle">Generated: $(date)</p>

    <div class="grid">
      <div class="card">
        <div class="stat-value">$BASELINE_NUM</div>
        <div class="stat-label">Baseline Edges</div>
      </div>
      <div class="card">
        <div class="stat-value">$MUTATOR_NUM</div>
        <div class="stat-label">Mutator Edges</div>
      </div>
      <div class="card">
        <div class="stat-value">$RUNS</div>
        <div class="stat-label">Executions</div>
      </div>
    </div>

    <div class="status $([ "$MUTATOR_NUM" -gt "$BASELINE_NUM" ] && echo 'improved' || ([ "$MUTATOR_NUM" -lt "$BASELINE_NUM" ] && echo 'regressed' || echo 'equal')">
      $STATUS
    </div>

    <h2>Coverage Comparison</h2>
    <div class="bar-container">
      <div class="bar-label">
        <span>Baseline</span>
        <span>$BASELINE_NUM edges</span>
      </div>
      <div class="bar-bg">
        <div class="bar-fill bar-baseline" style="width: 100%"></div>
      </div>
    </div>

    <div class="bar-container">
      <div class="bar-label">
        <span>Mutator</span>
        <span>$MUTATOR_NUM edges</span>
      </div>
      <div class="bar-bg">
        <div class="bar-fill bar-mutator" style="width: $(echo "scale=1; ($MUTATOR_NUM * 100) / ($BASELINE_NUM + 1)" | bc)%"></div>
      </div>
    </div>

    <div class="info">
      <h3>About This Report</h3>
      <p>This compares coverage between the baseline fuzzer and the structural mutator fuzzer.</p>
      <p>Baseline: $BASELINE</p>
      <p>Mutator: $MUTATOR</p>
      <p>Corpus: $CORPUS_DIR</p>
    </div>

    <footer>
      Generated by Garazyk Fuzzing Infrastructure
    </footer>
  </div>
</body>
</html>
EOF

echo ""
echo "=== Results ==="
echo "Baseline: $BASELINE_NUM edges"
echo "Mutator:  $MUTATOR_NUM edges"
echo "$STATUS"
echo ""
echo "Report: $REPORT"
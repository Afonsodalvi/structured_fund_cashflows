#!/usr/bin/env bash
set -euo pipefail

sfc_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$sfc_root"
for dependency in forge python3 slither; do
    command -v "$dependency" >/dev/null || { printf 'Missing dependency: %s\n' "$dependency" >&2; exit 1; }
done
mkdir -p coverage
python3 scripts/check_dependencies.py
python3 -m unittest discover -s scripts/tests -v
forge fmt --check
# Clear this isolated project's artifacts to avoid stale build-info in static analysis.
forge clean
FOUNDRY_PROFILE=ci forge test --summary --fuzz-seed 0x534643 | tee coverage/tests-ci.log
python3 scripts/check_candidate.py --manifest coverage/manifest.json | tee coverage/candidate-check.json
slither_run_dir="$(mktemp -d coverage/slither.XXXXXX)"
slither . --compile-force-framework foundry --foundry-ignore-compile \
    --filter-paths 'lib/|test/' --exclude-dependencies --fail-none \
    --json "$slither_run_dir/slither.json" >coverage/slither.log 2>&1
cp "$slither_run_dir/slither.json" coverage/slither.json
python3 scripts/check_slither.py coverage/slither.json | tee coverage/slither-gate.json
forge coverage --ir-minimum --fuzz-seed 0x534643 --report summary --report lcov >coverage/coverage.log 2>&1
python3 scripts/check_coverage.py lcov.info | tee coverage/coverage-summary.json
python3 scripts/write_validation.py
python3 scripts/check_editorial.py
python3 scripts/save_reports.py
python3 scripts/check_repository.py
printf 'Structured Fund Cashflows local verification passed. Reports: %s/coverage\n' "$sfc_root"

#!/usr/bin/env bash
set -euo pipefail

sfc_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$sfc_root"
export PATH="$sfc_root/.tools/foundry/bin:$sfc_root/.tools/security/bin:$sfc_root/.tools/editorial/bin:$PATH"
for dependency in forge python3 slither; do
    command -v "$dependency" >/dev/null || { printf 'Missing dependency: %s\n' "$dependency" >&2; exit 1; }
done
mkdir -p coverage
python3 scripts/check_dependencies.py
python3 -m unittest discover -s scripts/tests -v
forge fmt --check
python3 -c 'import json,sys; sys.path.insert(0,"scripts"); from write_validation import source_hashes; open("coverage/test-inputs.json","w").write(json.dumps(source_hashes(),sort_keys=True)+"\n")'
# Clear this isolated project's artifacts to avoid stale build-info in static analysis.
forge clean
FOUNDRY_PROFILE=ci forge test --summary --fuzz-seed 0x534643 --json-file coverage/tests-ci.json | tee coverage/tests-ci.log
forge test --match-test 'test_MaxFunctionsTrackCapPauseEligibilityAndClaimable|test_TransferMovesPrincipalProportionally|test_FullAsyncClaimRetiresSupplyAndPrincipal|test_SecuritySharesDoNotTransferDuringPause' -vvvv >coverage/source-map-evidence.log 2>&1
python3 scripts/check_candidate.py --manifest coverage/manifest.json | tee coverage/candidate-check.json
slither_run_dir="$(mktemp -d coverage/slither.XXXXXX)"
slither . --compile-force-framework foundry --foundry-ignore-compile \
    --filter-paths 'lib/|test/' --exclude-dependencies --fail-none \
    --json "$slither_run_dir/slither.json" >coverage/slither.log 2>&1
cp "$slither_run_dir/slither.json" coverage/slither.json
python3 scripts/check_slither.py coverage/slither.json | tee coverage/slither-gate.json
slither . --compile-force-framework foundry --foundry-ignore-compile \
    --filter-paths 'lib/|test/' --exclude-dependencies \
    --print inheritance-graph,function-summary,vars-and-auth \
    --json "$slither_run_dir/security-printers.json" >coverage/security-printers.log 2>&1
cp "$slither_run_dir/security-printers.json" coverage/security-printers.json
slither-check-erc . StructuredFundVault --erc erc20 --compile-force-framework foundry \
    --foundry-ignore-compile >coverage/erc20-conformance.log 2>&1
python3 scripts/security_diagrams.py
forge coverage --ir-minimum --fuzz-seed 0x534643 --report summary --report lcov --report attribution >coverage/coverage.log 2>&1
python3 scripts/check_coverage.py lcov.info | tee coverage/coverage-summary.json
python3 scripts/write_validation.py
python3 scripts/check_editorial.py
python3 scripts/save_reports.py
python3 scripts/check_repository.py
printf 'Structured Fund Cashflows local verification passed. Reports: %s/coverage\n' "$sfc_root"

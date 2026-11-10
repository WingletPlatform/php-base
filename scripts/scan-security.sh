#!/usr/bin/env bash

set -Eeuo pipefail

readonly TRIVY_IMAGE="aquasec/trivy:0.76.0"
readonly DEFAULT_SEVERITY="HIGH,CRITICAL"

usage() {
  echo "Usage: $0 <local-docker-image-reference>" >&2
  echo "Environment: FAIL_ON_FINDINGS=0|1 (default 0), SCAN_SEVERITY=LOW,MEDIUM,HIGH,CRITICAL (default HIGH,CRITICAL)" >&2
}

if [[ $# -ne 1 || -z "$1" ]]; then
  usage
  exit 2
fi

image_ref=$1
fail_on_findings=${FAIL_ON_FINDINGS:-0}
severity=${SCAN_SEVERITY:-$DEFAULT_SEVERITY}

if [[ "$fail_on_findings" != "0" && "$fail_on_findings" != "1" ]]; then
  echo "ERROR: FAIL_ON_FINDINGS must be 0 or 1" >&2
  exit 2
fi
if [[ ! "$severity" =~ ^(UNKNOWN,)?(LOW,)?(MEDIUM,)?(HIGH,)?(CRITICAL,)?(LOW|MEDIUM|HIGH|CRITICAL|UNKNOWN)$ ]]; then
  echo "ERROR: SCAN_SEVERITY must be a comma-separated list of Trivy severities" >&2
  exit 2
fi
if [[ ",$severity," != *,CRITICAL,* ]]; then
  echo "ERROR: SCAN_SEVERITY must include CRITICAL so the release policy cannot be weakened" >&2
  exit 2
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker is required to run the pinned Trivy container" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: Python 3 is required to summarize the Trivy JSON report" >&2
  exit 2
fi
if ! docker image inspect "$image_ref" >/dev/null 2>&1; then
  echo "ERROR: local Docker image '$image_ref' is unavailable; build or load the exact image before scanning" >&2
  exit 2
fi

report_dir=${SECURITY_REPORT_DIR:-.verification/security}
if ! mkdir -p "$report_dir"; then
  echo "ERROR: could not create the security report directory" >&2
  exit 3
fi
if ! report_dir=$(cd "$report_dir" && pwd); then
  echo "ERROR: could not resolve the security report directory" >&2
  exit 3
fi

human_report="$report_dir/report.txt"
json_report="$report_dir/report.json"
summary_report="$report_dir/summary.json"
tmp_human=''
tmp_json=''
tmp_summary=''
archive_file=''
archive_is_temporary=0
trivy_container="winglet-trivy-scan-$(date +%s)-$$-${RANDOM}"
cleanup() {
  [[ -z "$tmp_human" ]] || rm -f -- "$tmp_human"
  [[ -z "$tmp_json" ]] || rm -f -- "$tmp_json"
  [[ -z "$tmp_summary" ]] || rm -f -- "$tmp_summary"
  if [[ "$archive_is_temporary" == '1' && -n "$archive_file" ]]; then rm -f -- "$archive_file"; fi
  docker rm -f "$trivy_container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! tmp_human=$(mktemp "$report_dir/.report.XXXXXX"); then
  echo "ERROR: could not create a host-owned temporary human report in $report_dir" >&2
  exit 3
fi
if ! tmp_json=$(mktemp "$report_dir/.trivy.XXXXXX"); then
  echo "ERROR: could not create a host-owned temporary JSON report in $report_dir" >&2
  exit 3
fi
if ! tmp_summary=$(mktemp "$report_dir/.summary.XXXXXX"); then
  echo "ERROR: could not create a host-owned temporary summary in $report_dir" >&2
  exit 3
fi
printf 'Scanning exact local image %s with %s (severity %s)\n' "$image_ref" "$TRIVY_IMAGE" "$severity"
if [[ -n "${WINGLET_VERIFY_SAVE_IMAGE:-}" ]]; then
  archive_file=$WINGLET_VERIFY_SAVE_IMAGE
  if [[ ! -s "$archive_file" ]]; then
    echo "ERROR: verifier image archive '$archive_file' is missing or empty" >&2
    exit 3
  fi
else
  if ! archive_file=$(mktemp "${TMPDIR:-/tmp}/winglet-trivy-image.XXXXXX"); then
    echo "ERROR: could not create a temporary image archive" >&2
    exit 3
  fi
  archive_is_temporary=1
  if ! docker save --output "$archive_file" "$image_ref"; then
    echo "ERROR: could not archive the exact local image '$image_ref'" >&2
    exit 3
  fi
fi
if ! python3 - "$archive_file" "$image_ref" <<'PY'
import json, sys, tarfile
archive, image = sys.argv[1:]
with tarfile.open(archive, "r:*") as source:
    manifest_file = source.extractfile("manifest.json")
    if manifest_file is None:
        raise SystemExit("Docker image archive has no manifest.json")
    manifest = json.load(manifest_file)
if not any(image in (record.get("RepoTags") or []) for record in manifest):
    raise SystemExit("Docker image archive does not contain the requested image tag: " + image)
PY
then
  echo "ERROR: image archive does not match the requested local image '$image_ref'" >&2
  exit 3
fi
if ! docker image inspect "$TRIVY_IMAGE" >/dev/null 2>&1 && ! docker pull "$TRIVY_IMAGE"; then
  echo "ERROR: could not pull the pinned Trivy image '$TRIVY_IMAGE'" >&2
  exit 3
fi
if ! docker create --name "$trivy_container" --entrypoint trivy "$TRIVY_IMAGE" image \
  --input /tmp/winglet-image.tar \
  --scanners vuln \
  --severity "$severity" \
  --format json \
  --exit-code 0 >/dev/null; then
  echo "ERROR: could not create the Trivy scan container" >&2
  exit 3
fi
if ! docker cp "$archive_file" "$trivy_container:/tmp/winglet-image.tar"; then
  echo "ERROR: could not copy the exact local image archive to Trivy" >&2
  exit 3
fi
if ! docker start --attach "$trivy_container" >"$tmp_json"; then
  echo "ERROR: Trivy failed to generate the JSON report; no scan success is recorded" >&2
  exit 3
fi
if [[ ! -s "$tmp_json" ]]; then
  echo "ERROR: Trivy produced an empty JSON report" >&2
  exit 3
fi

if ! python3 - "$tmp_json" "$tmp_summary" "$image_ref" "$TRIVY_IMAGE" "$severity" "$fail_on_findings" <<'PY'
import json, sys
json_path, summary_path, image, scanner, severity, fail = sys.argv[1:]
with open(json_path, encoding="utf-8") as source:
    report = json.load(source)
counts = {"high": 0, "critical": 0, "fixable_critical": 0}
for result in report.get("Results") or []:
    for vulnerability in result.get("Vulnerabilities") or []:
        level = (vulnerability.get("Severity") or "").lower()
        if level in counts:
            counts[level] += 1
        if level == "critical" and vulnerability.get("FixedVersion"):
            counts["fixable_critical"] += 1
summary = {
    "image": image,
    "scanner": scanner,
    "scanner_version": scanner.rsplit(":", 1)[-1],
    "severity": severity,
    "policy": "fixable CRITICAL vulnerabilities",
    "fail_on_findings": fail == "1",
    "scanner_exit_codes": {"json": 0},
    "scan_status": "succeeded",
    "findings": counts,
    "policy_status": "findings" if counts["fixable_critical"] else "clear",
}
with open(summary_path, "w", encoding="utf-8") as output:
    json.dump(summary, output, indent=2)
    output.write("\n")
print("\nTrivy summary: HIGH={high}, CRITICAL={critical}, fixable CRITICAL={fixable_critical}".format(**counts))
PY
then
  echo "ERROR: could not parse Trivy JSON or write the scan summary; no scan success is recorded" >&2
  exit 3
fi

if ! python3 - "$tmp_json" "$tmp_summary" "$tmp_human" <<'PY'
import json, sys
json_path, summary_path, human_path = sys.argv[1:]
with open(summary_path, encoding="utf-8") as source:
    summary = json.load(source)
with open(json_path, encoding="utf-8") as source:
    report = json.load(source)
with open(human_path, "w", encoding="utf-8") as output:
    print("Trivy vulnerability report", file=output)
    print("Image: {}".format(summary["image"]), file=output)
    print("Scanner: {}".format(summary["scanner"]), file=output)
    print("Severity: {}".format(summary["severity"]), file=output)
    print("\nPackage | Vulnerability | Severity | Installed | Fixed", file=output)
    for result in report.get("Results") or []:
        for vulnerability in result.get("Vulnerabilities") or []:
            print("{} | {} | {} | {} | {}".format(
                vulnerability.get("PkgName", ""), vulnerability.get("VulnerabilityID", ""),
                vulnerability.get("Severity", ""), vulnerability.get("InstalledVersion", ""),
                vulnerability.get("FixedVersion") or "—"), file=output)
    print("\nScanner exit codes: json=0", file=output)
    print("Findings: HIGH={}, CRITICAL={}, fixable CRITICAL={}".format(
        summary["findings"]["high"], summary["findings"]["critical"], summary["findings"]["fixable_critical"]), file=output)
    print("Policy: {}; fail-on-findings={}".format(
        summary["policy_status"], str(summary["fail_on_findings"]).lower()), file=output)
PY
then
  echo "ERROR: could not generate the human-readable scan report" >&2
  exit 3
fi

if [[ ! -s "$tmp_human" || ! -s "$tmp_summary" ]]; then
  echo "ERROR: a generated scan report is empty" >&2
  exit 3
fi
if ! mv -f -- "$tmp_human" "$human_report"; then
  echo "ERROR: could not replace $human_report" >&2
  exit 3
fi
tmp_human=''
if ! mv -f -- "$tmp_json" "$json_report"; then
  echo "ERROR: could not replace $json_report" >&2
  exit 3
fi
tmp_json=''
if ! mv -f -- "$tmp_summary" "$summary_report"; then
  echo "ERROR: could not replace $summary_report" >&2
  exit 3
fi
tmp_summary=''

if ! python3 - "$summary_report" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    summary = json.load(source)
print("Scan status: {}; scanner exit code: json={}".format(summary["scan_status"], summary["scanner_exit_codes"]["json"]))
PY
then
  echo "ERROR: could not read the completed scan summary" >&2
  exit 3
fi

if [[ "$fail_on_findings" == "1" ]] && python3 - "$summary_report" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    raise SystemExit(0 if json.load(source)["findings"]["fixable_critical"] else 1)
PY
then
  echo "ERROR: security policy failed: fixable CRITICAL vulnerabilities were found" >&2
  exit 4
fi

echo "Security scan reports: $human_report $json_report $summary_report"

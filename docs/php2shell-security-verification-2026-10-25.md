# PHP 8.5 Base security verification follow-up

Date: 2026-10-25  
Repository: `wingletphp.base`

## Summary

Extended the existing Docker verifier to compare CLI PHP with Apache's HTTP PHP runtime, require PHP 8.5.12 or newer, check production error visibility/logging settings through CLI and HTTP, report the effective memory limit and PHP container memory constraint, and verify a controlled HTTP 500 followed by a successful PHP request. Existing upload-progress and `expose_php` checks and direct Apache security-header checks remain in place.

The verifier reports the Dockerfile's `FROM` reference, local image details when Docker has the base image tagged, and registry manifest information when `docker buildx imagetools` can provide it. Missing optional base-image inspection no longer fails a successful BuildKit build. It always inspects the locally built image after build. `PHP_VERSION`, `php -v`, and the Dockerfile source reference identify runtime and declared input; none alone establishes upstream source-patch provenance. A digest identifies image bytes and should be retained with registry provenance when available. Rebuilt images should not be described as official PHP images merely because they use the official image as a base.

## Changes

- `scripts/verify-php85.sh` adds PHP version agreement, `display_errors=Off`, `log_errors=On`, memory and `fatal_error_backtraces` reporting, Docker client/server and image/digest reporting, container memory-constraint reporting, and HTTP 500/continuity checks.
- `wingletphp.core/scripts/http-integration-smoke.sh` keeps required route, HTTP security, and CORS assertions in default mode. GH-24488 is now an opt-in isolated child-CLI check: `--simplexml-info` records a `KNOWN FAIL` without blocking unrelated HTTP checks; `--simplexml-strict` returns failure when evaluating a candidate fixed image.
- The repository contains no development PHP ini overlay or Apache `php_value`/`php_flag` override. This is a source review finding; application-level configuration is outside this Base repository.
- No PHP ini behavior was changed. PHP 8.5's `fatal_error_backtraces` defaults to On; the verifier records its actual CLI and Apache values. Fatal traces improve diagnostics but can expose stack and source details in logs. The PHP advisory identified enabled fatal backtraces as a stale-state trigger on affected pre-patch PHP 8.5; PHP 8.5.12 is the official fixed release for PHP2Shell, so the verifier's 8.5.12 minimum is the security control and the default is unchanged. `display_errors=Off` is checked for both SAPIs, while `log_errors=On` retains server-side diagnostics; keep logs access-controlled. See the [PHP runtime configuration manual](https://www.php.net/manual/en/errorfunc.configuration.php), [PHP2Shell advisory and fixed releases](https://www.php.net/), and [stale-state advisory](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
- The existing `session.upload_progress.enabled=Off` remains required. PHP's October 23 informational advisory describes another unusual upload-progress path when an application changes `session.serialize_handler` at runtime; disabling upload progress blocks that stated condition. This Base change does not alter session serialization behavior. See the [PHP advisory](https://www.php.net/).

## Verification

| Check | Result |
| --- | --- |
| Docker build, CLI/Apache runtime, ini values, headers, error continuity, memory, image digest | Not run in this Bridge task. The bounded catalog marks `scripts/verify-php85.sh` as requiring separately approved host permissions. |
| Base image identity and PHP version actually tested in this task | None; no container was run. The current Dockerfile declares `php:8.5.12-apache-bookworm`. |
| User-reported Base WSL result (2026-10-25) | Docker 29.6.1 built the image from official `php:8.5.12-apache-bookworm`, manifest digest `sha256:5e4418695f9b13b75edefaff547125bf6be267e865931731bdd5946461505736` (amd64 manifest `sha256:494239dde5d5b540543d681ab085e4dfa7029933b12efdb28acb246b68284092`); PHP 8.5.12, Composer 2.10.3, `memory_limit=128M`, `fatal_error_backtraces=1`, initial PHP security checks and Apache syntax passed, disposable container started, CLI PHP reported 8.5.12, and `HostConfig.Memory=0` (unlimited). After the published-port line, the supplied run exited with status 1 and no failure diagnostic or `Verification passed.` Source inspection identifies the cause: the HTTP fixture emits a final response line without a newline, and Bash `read` returns status 1 at EOF in that case; under `set -e`, the verifier exited silently despite having populated the parsed fields. The verifier now accepts a populated final line without a newline and reports an empty/unparseable fixture response explicitly. This root cause is proven by the source and matches the reported stopping point, but the fix has not yet been retested in WSL. This user run is failed, not a Base pass. This Bridge task did not run Docker. |
| PHP runtime for Bridge Core checks | PHP 8.5.9; Docker-specific checks were not run. |
| Development override review | Source reviewed; no repository-owned development ini or Apache PHP override found. |

WSL verification command with full log capture and exit-status reporting (run from the Base repository root):

```sh
mkdir -p .verification/php85
set -o pipefail
set +e
./scripts/verify-php85.sh 2>&1 | tee .verification/php85/verify-wsl.log
verify_status=$?
printf 'verify-php85 exit=%s\n' "$verify_status"
exit "$verify_status"
```

## Compatibility, deviations, and residual risks

- No application API, session, CORS, authentication, or JWT behavior changed. Normal multipart uploads remain enabled; only session upload-progress remains disabled.
- `memory_limit` is reported, not changed. Container memory is reported from `HostConfig.Memory`; zero means Docker did not set a per-container limit.
- Base-image local inspect and registry digest lookup are optional; their absence is recorded and does not conceal or bypass the required built-image/runtime checks.
- The user-reported PHP 8.5.12 image reproduces the upstream SimpleXML GC regression (GH-24488) when a property table is materialized and its object is later collected in a cycle. Upstream PR 24494 was closed after a fix commit was linked on October 22, 2026, but no released PHP build or candidate Docker image was verified here. Core's follow-up report records the JSON path and strict isolated smoke mode; run it against the selected image before considering the issue cleared. See the upstream [issue](https://github.com/php/php-src/issues/24488) and [fix PR](https://github.com/php/php-src/pull/24494).
- User-reported Core WSL run used `akikettu/wingletbase:v0.4.0-RC1`, digest `akikettu/wingletbase@sha256:93b65a8dec5c530bac42ec800102185f3ecf3f6d15b3ff8e73d9539ef5362c6d`, and PHP 8.5.12. The isolated SimpleXML child CLI process crashed with `zend_mm_heap corrupted`, while Apache `/smoke/ready` still returned 200. This is upstream behavior, remains unfixed by Core, and was not reproduced in this Bridge task.

Run from the Core repository root on a Docker-capable WSL host:

```sh
./scripts/http-integration-smoke.sh
WINGLET_BASE_IMAGE=akikettu/wingletbase:v0.4.0-RC1 ./scripts/http-integration-smoke.sh --simplexml-info
WINGLET_BASE_IMAGE=<candidate-fixed-image> ./scripts/http-integration-smoke.sh --simplexml-strict
```

The default invocation is the required independent HTTP/CORS gate. Informational mode prints and retains `KNOWN FAIL` if the probe crashes, without claiming the upstream issue is fixed; strict mode exits unsuccessfully and is intended to evaluate a candidate fixed PHP image.

## Files

- `scripts/verify-php85.sh`
- `docs/php2shell-security-verification-2026-10-25.md`
- `../core/scripts/http-integration-smoke.sh`
- `../core/docs/php85-simplexml-regression-2026-10-25.md`

## Core HTTP and SimpleXML regression

Core's required smoke checks routes, generic 500 responses, security headers, ordinary OPTIONS, exact-origin CORS, denied preflights, and CORS error responses. The SimpleXML probe runs only when explicitly selected and after the HTTP assertions. Core PHPUnit (166 tests/661 assertions), PHPStan, and `composer validate --strict` passed through the bounded Bridge catalog. Docker build and HTTP checks remain unrun here.

See [Core's GH-24488 notes](../../core/docs/php85-simplexml-regression-2026-10-25.md) for the observed output and mode behavior.

## Definition of done

- [x] Missing local FROM tag no longer fails a successful BuildKit build; mandatory built-image/runtime checks remain.
- [x] Default Core HTTP/CORS smoke is independent of GH-24488.
- [x] The optional probe records `KNOWN FAIL` or strict failure without misrepresenting the upstream bug as fixed.
- [x] Core bounded PHPUnit, PHPStan, and Composer validation passed.
- [ ] The supplied Base WSL run failed with exit 1 immediately after published-port discovery; the exact source cause is the no-newline fixture response passed to `read` under `set -e`. This has been fixed in the verifier but awaits the WSL retest above. Docker-specific Base and Core checks were not run in this Bridge task, so Base is not called passed.

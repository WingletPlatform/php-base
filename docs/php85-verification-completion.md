# PHP 8.5 verification task completion

Date: 2026-10-22

## Summary

Added permanent, developer-runnable PHP 8.5 verification entry points for Base and Core and connected them to the existing Bitbucket main, pull-request, and version-tag pipelines. Existing migration work and unrelated working-tree changes were preserved.

## Changes

- Base: `scripts/verify-php85.sh` builds this repository's Dockerfile for `linux/amd64`, checks PHP 8.5.12, required extensions, Composer, PHP hardening, Apache configuration, and isolated Apache/front-controller HTTP smoke responses. It records a log and JSON summary under `.verification/php85/`, cleans up only its uniquely named local resources, and can save the built image for the existing scan/publish steps.
- Base: default, PR, main, and tag pipelines now call the script and retain its logs/summary as artifacts. Main/tag image artifacts continue to the existing scanner and publish steps.
- Core: `bin/ci/verify-php85.sh` enforces PHP 8.5.x, validates Composer metadata, installs locked dependencies, checks platform requirements, lints source/tests/configuration, and runs PHPStan and PHPUnit. Bitbucket default, PR, and tag pipelines use this shared entry point and retain artifacts.
- Core: tests now cover denied-origin OPTIONS preflight and CORS headers on handled 500 responses.
- Both migration guides document local commands, CI behavior, artifacts, and the separate live HTTP integration gate. Generated verification output is ignored by Git.

## Files changed by this task

- Base: `.gitignore`, `bitbucket-pipelines.yml`, `docs/php85-migration.md`, `docs/php85-verification-completion.md`, `scripts/verify-php85.sh`.
- Core: `.gitignore`, `bitbucket-pipelines.yml`, `bin/ci/verify-php85.sh`, `docs/php85-cors-migration.md`, `tests/Kernel/HttpKernelTest.php`, `tests/Unit/Http/CorsMiddlewareTest.php`.

Other pre-existing modifications in both repositories were present before this task and were left intact.

## Verification

- Read both repository states and the applicable root `AGENTS.md`; confirmed there are no repository-level or nested `AGENTS.md` files.
- Queried the bounded normal-test catalog for both repositories. Base exposed only the new Docker-backed script, marked as requiring host permissions; Core exposed no catalog tests.
- No Docker build/container execution, Composer validation/install, PHPUnit, PHPStan, live HTTP check, or Bitbucket CI run was performed. No test pass is claimed.
- Shell syntax and YAML/Composer validation remain to be checked in an approved environment or CI.

## Deviations and outstanding gates

- Bridge exposed no archive-creation tool. Per the handoff, separate changed-file-only ZIP archives were not created; source changes remain in their repositories. The existing Base ZIP was not changed and is not represented as a new deliverable.
- Core unit/kernel tests exercise the real in-process request pipeline, including CORS and handled errors. A live application-backed HTTP run through the Base image is still an explicit release gate because the repos do not provide a portable application fixture or a stable published Base image digest for cross-repository CI.
- Required follow-up: run Base verification on a developer Docker host or Bitbucket; run Core PHP 8.5 verification in CI; execute the external HTTP integration gate before release.

## Risks and definition of done

Runtime build and HTTP behavior remain unverified until the above gates run. CI is configured to fail when its PHP 8.5 checks or Base image smoke checks fail, and existing release actions remain downstream of those checks. Source changes, tests, pipeline wiring, and documentation are complete; operational verification and archive packaging remain outstanding.

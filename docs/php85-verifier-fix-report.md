# PHP 8.5 verifier fix report

## Summary

Updated the Base PHP 8.5 verifier to accept PHP's empty-string representation of disabled boolean ini values, emit clear property/expected/actual diagnostics, preserve its locally built image when `KEEP_IMAGE=1`, and check the real `Server` and `X-Powered-By` response headers through a disposable Apache container with no Core dependency. Default cleanup targets only resources created by this run. The PHP and Apache runtime settings and CI pipeline were not changed.

## Files

- `scripts/verify-php85.sh`
- `docs/php85-migration.md`
- `docs/php85-verifier-fix-report.md`

## Verification

- No Docker command or end-to-end verifier run was performed. The task handoff says the existing PHP 8.5.12 image build succeeded and its disabled settings were observed, but those observations do not validate this verifier change.
- The bounded normal-test catalog exposed only the Docker-based verifier, marked as requiring host permissions. It was not run.
- No bounded shell syntax checker was available, so shell syntax remains unverified.
- The changed-file ZIP was not created because no bounded archive tool is available and arbitrary host commands are disallowed for this task.

## Deviations and risks

- End-to-end behavior, including actual HTTP headers and cleanup on failure, still needs a local or CI verifier run. Do not treat this report as a passed runtime verification.
- Changed-file paths for the requested archive are `scripts/verify-php85.sh`, `docs/php85-migration.md`, and this report. Their repository-relative paths are preserved here for archive creation.

## Definition of done

- Requested verifier and migration-document updates are present.
- In the earlier verifier-fix change summarized above, no Core files, Docker/Apache/PHP runtime settings, CI pipeline configuration, commits, pushes, or deployment were changed.
- Docker runtime verification, shell syntax validation, and archive creation remain unverified or unavailable as described above.

## Standalone Base HTTP smoke update (2026-10-22)

- Replaced the `/` front-controller probe and synthetic Core autoloader with a temporary `__verify_php85.php` file, mounted read-only at its exact document-root path. Its directory and file permissions allow Apache's `www-data` worker to read and execute it.
- The verifier now treats receipt of any HTTP status as transport readiness, then separately requires HTTP 200 and the expected PHP-generated body. It checks `Server: Apache` and absence of `X-Powered-By` on that same response. A reachable HTTP 500 therefore fails the fixture check, not readiness.
- Updated `docs/php85-migration.md` to explain direct-file Apache rewrite behavior and that integrated Core front-controller behavior belongs to a later integration gate.
- Static inspection only; no Docker/runtime or bounded normal test was run. The existing `wingletphp.base-task-20261022.zip` contains a broader earlier file set and was left untouched; no bounded archive-creation tool is available to create a fresh changed-files-only ZIP.

## HTTP smoke and Apache ServerName follow-up (2026-10-22)

- Both disposable HTTP containers now explicitly publish port 80 to a random host port bound to `127.0.0.1`. The verifier retries mapped-port lookup through Docker container metadata and retries HTTP readiness for a bounded period; failures include container state, port mappings, and logs.
- Apache now loads a global `ServerName localhost` directive through `/etc/apache2/conf-enabled/servername.conf`, suppressing the startup `AH00558` warning without changing virtual-host routing.
- The migration guide documents the binding, readiness behavior, and Apache setting. Existing `KEEP_IMAGE=1`, unique disposable resource cleanup, CI failure behavior, and response-header checks (`X-Powered-By` absent and `Server: Apache`) are retained.
- Files touched in this follow-up: `Dockerfile`, `apache/servername.conf`, `scripts/verify-php85.sh`, `docs/php85-migration.md`, and this report.
- `git diff --check` passed for tracked changes, and the final source diff was reviewed. No Docker, Apache runtime, or HTTP check was run. The bounded normal-test catalog exposes only the Docker-backed verifier, marked as requiring host permissions, so it was not run. No archive-creation tool is available; the changed-files-only ZIP was not produced.

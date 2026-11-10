# PHP 8.5 Base final acceptance prep

Date: 2026-10-22  
Repository: `wingletphp.base`

## Summary

Extended the existing Base PHP 8.5 verifier with disposable checks for cron and Apache startup, bind-mounted runtime directory ownership and modes, setup idempotence, and container shutdown. The existing Bitbucket default, pull-request, main, and tag pipelines already run this verifier, so those checks are now part of each of those gates. Updated the migration guide with the reported prior results and the still-pending clean build and scanner gates.

## Changes

- `scripts/verify-php85.sh` creates unique temporary cache/log/var bind mounts, verifies the startup script normalizes their directories and fixture files to the expected `www-data` ownership and permissions, reruns setup to check idempotence, confirms cron and Apache processes are running, and checks that the disposable container stops with exit code 0. Cleanup restores ownership only on the verifier's unique fixture paths and removes only its own resources.
- `docs/php85-migration.md` records reported prior Base and Core results, distinguishes those from checks not run in this task, and documents clean no-cache build and local Trivy commands. Trivy's existing release behavior is clarified: main and tag pipelines scan CRITICAL findings with Trivy 0.50.2; default and pull-request pipelines do not scan.

## Files

- `scripts/verify-php85.sh`
- `docs/php85-migration.md`
- `docs/php85-final-acceptance-prep.md`

## Verification

- The task handoff reports a prior local Base verifier pass using a cached `linux/amd64` image build, PHP 8.5.12, extensions, Composer 2.10.3, PHP security settings, Apache syntax, and an isolated PHP fixture returning HTTP 200 with `Server: Apache` and no `X-Powered-By`. This task did not rerun that test.
- The handoff reports Core PHPStan passing on 165 files and PHPUnit passing 158 tests / 600 assertions on host PHP 8.5.9. Core is outside this task's write scope and was not inspected or changed.
- The bounded Base test catalog contains only `scripts/verify-php85.sh`, marked as requiring host permissions. It was not run; no Docker command was executed through Bridge.
- The new cron, bind-mount, idempotence, and stop checks therefore remain unverified. A clean `--no-cache` build, this task's Bitbucket CI run, and Trivy scan also remain unverified.
- No source-only check was available in the bounded test catalog.

## Deviations and risks

- The prior reported Base run used cached layers and does not establish a clean no-cache build. The clean build and local scanner commands are in `docs/php85-migration.md`.
- Bitbucket runs the Trivy gate only on main and version-tag pipelines. Pull requests and default-branch runs get the image verification checks but not an image scan.
- A changed-files-only ZIP was not produced: no bounded archive-creation operation is available, and arbitrary host commands are disallowed for this task. The earlier `wingletphp.base-task-20261022.zip` was left untouched. Changed paths are listed above.
- Existing Base working-tree edits and reports were present before this task. No Core files, deployment settings, commits, pushes, or external resources were changed.

## Definition of done

- Source now includes the requested reproducible lifecycle and bind-mount checks, wired through the existing Bitbucket verifier steps.
- The guide records what the handoff says passed and clearly identifies the clean build, newly added runtime checks, CI, and Trivy scan that still need execution.
- Operational acceptance is not established until those pending gates pass.

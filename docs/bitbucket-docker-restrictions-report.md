# Bitbucket Pipelines Docker restrictions report

Date: 2026-10-22

## Summary

Updated the PHP 8.5 verifier and Trivy scanner to work without Docker bind mounts or Docker socket mounts. Existing runtime startup and release security checks remain in place. The Bitbucket main/tag scan now reads the same `image.tar` artifact that the later publish step loads, and the scanner checks that the requested image tag is present in the archive.

## Changes

- `scripts/verify-php85.sh` now creates the disposable container, copies in the HTTP and restrictive runtime fixtures with `docker cp`, then starts the container. The existing HTTP response/header, cron, runtime ownership and modes, idempotence, and graceful-stop assertions remain. Cleanup no longer has a mount-based ownership-restoration fallback because these fixtures are inside the disposable container. When `WINGLET_VERIFY_SAVE_IMAGE` is set, the verifier preserves the successfully built image for the following scan.
- `scripts/scan-security.sh` no longer requires or mounts `/var/run/docker.sock`, and no longer mounts a cache. It scans an image archive using the pinned Trivy container's `--input` mode. In CI it reads `WINGLET_VERIFY_SAVE_IMAGE` (the verifier's `image.tar`); locally it exports the requested Docker image with `docker save`. It checks `manifest.json` for the requested image tag before scanning. Trivy's JSON output generates both the detailed text report and the policy summary; the fixable CRITICAL release gate is unchanged.
- `docs/php85-migration.md` documents the copy-based fixture checks, archive-based scan, cache behavior, and what remains unverified.
- The pipeline already creates `image.tar`, scans before publishing, and later loads that artifact for publication, so its command order did not need modification.

## Files changed

- `scripts/verify-php85.sh`
- `scripts/scan-security.sh`
- `docs/php85-migration.md`
- `docs/bitbucket-docker-restrictions-report.md`

## Verification

- `bash -n scripts/verify-php85.sh scripts/scan-security.sh` passed.
- `git diff --check` passed.
- Static inspection confirmed there are no Docker `--mount` uses or Docker socket references in either modified script. The pipeline's main/tag steps pass the same `image.tar` path to the verifier and scanner, then the publish step loads `image.tar`.
- The bounded normal-test catalog exposes `scripts/verify-php85.sh`, which requires host permissions. Docker build, HTTP, cron, ownership/idempotence, Trivy execution, and Bitbucket CI were not run in this task.

## Host/CI verification plan

Run the existing Bitbucket main or version-tag pipeline. Its verification step runs `./scripts/verify-php85.sh`, then `FAIL_ON_FINDINGS=1 ./scripts/scan-security.sh "$WINGLET_VERIFY_IMAGE"` with `WINGLET_VERIFY_SAVE_IMAGE=image.tar`; the later publish step runs `docker load -i image.tar` before tagging and pushing. Confirm the verifier's HTTP, cron, runtime permissions/idempotence, and stop checks pass, the scanner report names the expected image and policy status, and publication uses the same tar artifact.

## Deviations and risks

- No pipeline YAML edit was needed because the current main/tag steps already save the verifier image, scan in the same step, retain `image.tar`, and publish by loading that artifact.
- Docker and Bitbucket plugin behavior could not be executed here. In particular, the Docker service must allow the existing loopback port publication and `docker cp`; these commands avoid the reported forbidden mount operation.
- Trivy now has an ephemeral in-container database cache, so a CI scan may download the database on each run. The fixed scanner version, HIGH/CRITICAL reporting, and fixable CRITICAL failure policy remain unchanged.

## Definition of done

The mount and socket-mount invocations are removed from the verifier and scanner, runtime/HTTP/security assertions are retained, the CI scan input is tied to the archive later loaded for publishing, and the change has passed the available static checks. Docker and Bitbucket execution remain to be confirmed by the host/CI plan above.

# PHP 8.5.13 upgrade report

**Date:** 2026-11-19  
**Repository:** `WingletPlatform/php-base`  
**Initial Git state:** clean, branch `main`, tracking `origin/main`

## Changes

- `Dockerfile`: changed the official PHP Apache base tag from `php:8.5.12-apache-bookworm` to `php:8.5.13-apache-bookworm`. Bookworm and Apache remain unchanged.
- `scripts/verify-php85.sh`: raised the verifier minimum from PHP 8.5.12 to 8.5.13, including its failure and summary metadata, so the image check rejects the previous release.

Upstream confirms PHP 8.5.13 is a security release ([PHP announcement](https://www.php.net/releases/8_5_13.php)). Docker Hub lists the official Bookworm tag for `linux/amd64`; the current multi-platform index digest is `sha256:ec28324630bc77e2687a96216b4839ecbf7dbcfa686628521c23e0a0844d789d` and the amd64 manifest digest is `sha256:e9e9a6b8a785f29d93d4d7d25cdce246c1f3b6fc1612a4d482425a940c838165` ([Docker Hub image details](https://hub.docker.com/layers/library/php/8.5.13-apache-bookworm/images/sha256-e9e9a6b8a785f29d93d4d7d25cdce246c1f3b6fc1612a4d482425a940c838165)). The Dockerfile remains tag-based; no digest was added.

## Verification

- `bash -n scripts/verify-php85.sh`: passed.
- Docker access became available on the latest continuation; `docker version` reported client and server 29.10.0.
- The repository verifier passed on `linux/amd64` for local image `winglet-base-php85-8.5.13-final:20261119`. Built image ID and local digest: `sha256:233749b40a2c61313715536f77ecd9552c6c74d30b1d4870d49e1398bc2380ce`. BuildKit resolved the official base tag to index digest `sha256:ec28324630bc77e2687a96216b4839ecbf7dbcfa686628521c23e0a0844d789d`, amd64 manifest `sha256:e9e9a6b8a785f29d93d4d7d25cdce246c1f3b6fc1612a4d482425a940c838165`.
- Runtime checks passed: CLI and Apache HTTP PHP both reported 8.5.13; required extensions (`pdo_mysql`, `fileinfo`, `gd`, `zip`, `apcu`) and security settings passed; Composer 2.11.2 was present; `apache2 -v` reported Apache/2.4.71 (Debian); Apache configtest passed. HTTP checks returned 200 for the PHP fixture, 500 for the controlled error followed by a successful request, `Server: Apache`, and no `X-Powered-By`. Cron and Apache started, runtime directory ownership/modes and idempotence passed, and the container stopped with exit code 0. Memory constraint was 0 (unlimited).
- Dockerfile lint passed using the CI-equivalent `docker run --rm -i hadolint/hadolint:latest-alpine < Dockerfile` command. `git diff --check` passed.
- Trivy 0.76.0 scan passed using `FAIL_ON_FINDINGS=1` and severity `HIGH,CRITICAL`: 198 HIGH, 4 CRITICAL, 0 fixable CRITICAL; the configured fixable-CRITICAL policy was clear. Findings are recorded in `.verification/security/report.txt` and `.verification/security/report.json`; they are not hidden. The scan detected Debian 12.15 OS packages and no language-specific files.
- GitHub Actions itself was not run; the equivalent Dockerfile lint, repository verifier, and main-branch Trivy scan steps were run locally.

## Release state

The verified image remains local as `winglet-base-php85-8.5.13-final:20261119`; no image was published, no push or commit was made, and no production environment was changed. The working tree contains only the two source changes above and this report. `.verification/` holds ignored verifier and Trivy artifacts.

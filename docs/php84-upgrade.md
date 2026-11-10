# Superseded PHP 8.4 transition draft

This earlier draft is retained for history. Its PHP 8.4 target and verification notes are superseded by [the PHP 8.5 migration guide](php85-migration.md).

# Winglet Base: PHP 8.4 transition (2026-10-22)

## Actual changes

- Base image `php:8.5.7-apache` -> `php:8.4-apache-bookworm` (rolling official PHP 8.4 / Debian Bookworm tag).
- Disable `session.upload_progress.enabled` in PHP. This does **not** disable normal PHP sessions or multipart file uploads. Any application requiring PHP's built-in session-based upload progress feature must be audited separately.
- Preserve all installed extensions, Apache modules, cron, Composer setup, runtime directories, image structure and service startup behavior.
- Core (`winglet/core`) does not require a change: Composer requires `php: ^8.4` and its platform is `8.4.0`.

## Critical security verification before deployment

On 2026-10-21, PHP 8.4.27 fixed critical web-request RCE vulnerabilities. The rolling Docker tag must be freshly pulled and must resolve to **PHP >= 8.4.27** at build time. Do not deploy an older cached 8.4 image. After building:

```sh
docker build --pull --no-cache -t wingletbase:php84 .
docker run --rm wingletbase:php84 php -r 'echo PHP_VERSION, "\n";'
docker run --rm wingletbase:php84 php -i | grep -i 'session.upload_progress.enabled'
docker run --rm wingletbase:php84 php -m
docker run --rm wingletbase:php84 apache2ctl -M
```

Verify extensions include `pdo_mysql`, `fileinfo`, `gd`, `zip`, `apcu`; `session.upload_progress.enabled => Off`. For a reproducible production release, record and pin the verified image digest, then rebuild regularly for security updates.

## Downstream validation gate

1. Build Base on CI with `--pull` and inspect PHP patch release.
2. Run Core's `./bin/ci/check.sh` in a PHP 8.4 environment with Composer dependencies installed.
3. Build a real consumer application image and smoke test startup, routes, authentication, sessions, Doctrine, DB connection, cron and file uploads.
4. Verify reverse-proxy setup and trusted forwarded-IP ranges; existing `RemoteIPTrustedProxy 172.0.0.0/8` is too broad for an unverified network topology. Restrict in a separately validated config change.
5. Review Composer installer integrity and current Trivy version in CI before release; neither was changed in this targeted patch.

## Validation completed in this draft

- Static inspection of supplied Base and Core archives.
- PHP 8.4.24 syntax-check (`php -l`) of 172 Core PHP files: passed.
- No Docker daemon/CLI available; image build and container smoke tests **not performed**.
- No Core vendor directory in archive; Composer install, PHPStan and PHPUnit **not performed**.

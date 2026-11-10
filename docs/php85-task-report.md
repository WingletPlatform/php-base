# Base PHP 8.5 task report

Date: 2026-10-22

## Summary

Moved the Base image to the published PHP 8.5.12 Apache Bookworm tag and removed the Base-level wildcard CORS behavior. Added PHP and Apache disclosure hardening, Composer installer signature verification, and an amd64 CI smoke gate. See [php85-migration.md](php85-migration.md) for deployment and migration details.

## Changes

- Dockerfile pins `php:8.5.12-apache-bookworm`, validates the Composer installer SHA-384 signature, and copies PHP and Apache security configuration.
- PHP disables session upload progress and `expose_php`; Apache reduces version disclosures.
- The front controller no longer emits CORS headers or short-circuits every OPTIONS request.
- CI pulls the selected image, targets linux/amd64, and checks PHP version, required extensions, upload-progress configuration, and Apache configuration before scanning.
- `RemoteIPTrustedProxy 172.0.0.0/8`, startup ownership normalization, the Composer version channel, unpinned APT/PECL package resolution, and Trivy 0.50.2 were reviewed and retained with risks documented because build/deployment topology and validation were unavailable.

## Files in this repository's delivery bundle

- `Dockerfile`
- `apache/security.conf`
- `bitbucket-pipelines.yml`
- `docs/php85-migration.md`
- `docs/php84-upgrade.md` (retained and explicitly marked as superseded historical draft)
- `html/index.php`
- `php/99-security.ini`

The pre-existing `docs/php84-upgrade.md` draft was superseded by `docs/php85-migration.md`. Existing unrelated working-tree files were not included.

## Verification

- Official Docker Library manifest lists `php:8.5.12-apache-bookworm` for amd64; php.net identifies PHP 8.5.12 as a security release.
- Bounded normal-test catalog: no Base tests available.
- Docker build, in-image `php -v` / `php -m`, Apache startup, route and CORS smoke tests, cron, and Trivy scan: not run. CI checks were added but are not yet run.

## Deviations and risks

- Exact Debian and PECL APCu package versions remain build-time resolved. Composer installs its latest stable version after verifying the installer signature; record the actual Composer version from a successful CI image.
- Forwarded client IP trust remains broad until operators can validate the Traefik Docker subnet and prevent untrusted peers from joining it.
- Existing cron child supervision and recursive ownership normalization need deployment-level validation.
- This report and the migration document are not a substitute for the CI/build verification gate.

## Definition of done

- PHP image pin, PHP hardening, Base CORS removal, CI smoke checks, and migration guidance are implemented.
- Build/runtime checks and cross-service integration remain pending; no deployment or push was performed.

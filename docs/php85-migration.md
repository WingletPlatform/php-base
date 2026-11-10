# Winglet PHP Base: PHP 8.5 and runtime migration

Date: 2026-10-22

## Image and package state

- Base image is pinned to the published official tag `php:8.5.12-apache-bookworm`. The official `docker-library/official-images` manifest lists this Apache/Bookworm tag for `amd64`. PHP 8.5.12 was published as a security release on 2026-10-21. Docker build/runtime verification is still required before release.
- Docker builds and tagged pipeline builds now request `linux/amd64` and `--pull`. The pipeline runs `php -v`, checks the declared PHP extensions and upload-progress setting, and validates Apache configuration before scanning.
- Extensions built/enabled by this image: `pdo_mysql`, `fileinfo`, `gd`, `zip`, and PECL `apcu`. No extension was removed. Their runtime presence has not been confirmed in this environment because the image was not built.
- APT packages are resolved from Debian Bookworm at build time; exact package versions are not pinned. PECL APCu is installed without a version pin. Review build output and pin a tested APCu release if reproducibility is required.
- Composer is downloaded at image build from `getcomposer.org`; the SHA-384 installer signature is checked against Composer's published signature before execution. The installer selects its current stable Composer release, so the Composer version is intentionally not fixed and must be recorded from a built image (`composer --version`).
- No application/library package versions are installed by Base itself.

## Runtime security changes

- PHP uses `php.ini-production`; `session.upload_progress.enabled` is explicitly Off. PHP sessions and multipart file uploads remain enabled. Applications that rely on the optional session upload-progress feature must migrate or explicitly assess that requirement.
- `expose_php` is Off. Apache uses `ServerTokens Prod` and `ServerSignature Off` to reduce version disclosure, and sets the global `ServerName` to `localhost` to avoid the startup `AH00558` warning.
- The Base front controller no longer emits wildcard CORS headers or answers every `OPTIONS` request itself. Core owns configured CORS and preflight processing. Applications that depended on wildcard CORS must add explicit Core configuration.
- `.htaccess` files and legacy `php_flag`/`php_value` directives were not found in this repository, so no PHP 7 Apache directives needed replacement.

## Proxy, startup, and CI findings

- `RemoteIPTrustedProxy 172.0.0.0/8` remains in place. This image is commonly deployed behind Traefik on Docker networks, and the actual network topology and address allocation are not present here. Narrowing the range without those facts could stop real client IP forwarding; operators should restrict trust to the Docker subnet(s) actually used by the proxy and prevent untrusted containers from joining those networks. Apache RemoteIP changes the client address used by Apache logs and applications; it does not configure routing or firewall trust.
- Startup creates runtime directories as `www-data` and recursively normalizes ownership and group-write permissions under `/var/www/cache`, `/var/www/logs`, and `/var/www/var`. Bind-mounted paths must permit the container's `www-data` UID/GID to write; large prepopulated mounts may make startup chown slow.
- `start-services` backgrounds cron then `exec`s Apache in the foreground. Apache receives container stop signals as PID 1; cron is not separately supervised. Validate cron execution and shutdown behavior in the deployed image before changing this established runtime convention.
- The shared scanner is pinned to `aquasec/trivy:0.76.0` (verified against the upstream release list on 2026-10-22). Reports include HIGH and CRITICAL vulnerabilities. Main and version-tag builds fail only when a CRITICAL record has a nonempty Trivy `FixedVersion`; HIGH findings and CRITICAL findings without a Trivy fix version are informational. This is equivalent to the previous CRITICAL-only gate with `--ignore-unfixed`, while keeping unfixed findings visible in reports. See the [2026-10-22 Trivy findings analysis](php85-trivy-findings.md) for the local scan's package/CVE breakdown and caveats.

## Downstream migration checklist

1. Rebuild with `docker build --pull --platform linux/amd64` and record `php -v`, `composer --version`, `php -m`, `php --ini`, and `apache2ctl -M` output.
2. Confirm `pdo_mysql`, `fileinfo`, `gd`, `zip`, and `apcu` are loaded, and `session.upload_progress.enabled` and `expose_php` are Off.
3. Start the image with the production bind mounts. Verify writable cache/log/var paths, Apache startup, graceful stop, scheduled cron tasks, and application CLI commands.
4. Verify API GET/POST/error response behavior and CORS preflights for allowed/denied origins and disabled configuration. Remove downstream wildcard CORS settings and set explicit Core origins, methods, and headers.
5. Confirm Traefik's Docker subnet(s), restrict `RemoteIPTrustedProxy` accordingly in the service-specific deployment, and test that arbitrary untrusted peers cannot supply `X-Forwarded-For`.
6. Run each downstream application's unit/static checks and upload/session/Doctrine/database smoke tests on PHP 8.5 before rollout.
7. Run the pinned Base Trivy policy in main/tag CI and review every HIGH/CRITICAL finding before release.

## Verification status

- Published image tag and `amd64` architecture: confirmed from the official Docker Library PHP manifest.
- PHP release status: PHP 8.5.12 is listed by php.net as a security release.
- Docker build, `php -v` in a built container, `php -m`, Apache startup, application routes, CORS wire behavior, cron, and Trivy scan: not run here. The task environment did not provide an approved local Docker build gate; the pipeline checks added here remain to be run in CI.

## Bridge follow-up verification (2026-10-22)

- Read-only inspection reconfirmed the Dockerfile uses `php:8.5.12-apache-bookworm`, builds `pdo_mysql`, `fileinfo`, `gd`, and `zip`, installs APCu, validates the Composer installer signature, and copies the Apache/PHP security configuration. These are source declarations, not observed image contents.
- The bounded Bridge normal-test catalog returned no tests for `wingletphp.base`. The bounded Docker verification interface requires a profile ID, but this task exposed no profile discovery or approved profile ID. No Docker daemon or host-level command was run, so newly granted build permission is **unverified** and no local image build was attempted.
- No runtime result is available for PHP/module versions, Composer version, Apache config/modules, startup/shutdown, cron, upload/session behavior, HTTP responses, or Trivy. The existing CI definition contains build and smoke steps, but it has not run as part of this verification.
- No migration-induced defect was confirmed from static inspection alone; no code fix was made during this follow-up.
- The existing documentation's downstream checklist remains the required runtime follow-up once an approved, task-scoped builder is exposed. In particular, confirm the actual Traefik network topology before changing `RemoteIPTrustedProxy` and review the pinned Trivy version/findings with real scan evidence.

## Repeatable verification

Run the verifier locally from this repository when Docker Engine and `curl` are available:

```sh
./scripts/verify-php85.sh
KEEP_IMAGE=1 ./scripts/verify-php85.sh
```

The script builds this Dockerfile for `linux/amd64`, verifies PHP 8.5.12, the required extensions, Composer, disabled PHP hardening settings, Apache configuration, cron and Apache process startup, runtime directory ownership/modes, runtime directory setup idempotence, and a graceful container stop. It creates unique disposable fixture paths and removes only its own container and image. To work with restricted Docker services, the verifier creates the container first, copies deliberately restrictive cache/log/var fixtures and a disposable `__verify_php85.php` file into it with `docker cp`, then starts it. Startup must normalize the staged runtime files to the expected `www-data` ownership and modes. The HTTP fixture is copied to `/var/www/html/__verify_php85.php`; Apache's rewrite rule passes an existing file through unchanged, so its direct URL bypasses the production front controller without changing `html/index.php` or adding anything to the image. Its PHP response and real response headers are checked: HTTP transport readiness accepts any HTTP status, then the fixture test separately requires status 200, the expected body, `X-Powered-By` absent, and `Server` exactly `Apache` (`ServerTokens Prod`). A reachable HTTP 500 is therefore reported as a fixture/test failure rather than an Apache readiness failure. Core's integrated front-controller behavior remains a downstream integration check, not a Base-only readiness requirement. The container explicitly publishes port 80 to a Docker-assigned host port bound to `127.0.0.1`; the verifier retries container metadata lookup and HTTP readiness with bounded waits, then prints container state and logs if no HTTP response arrives.

By default, cleanup removes only the containers created by this run and its locally built image. It does not remove pre-existing or external Docker resources. `KEEP_IMAGE=1` preserves the built image after either success or failure and prints its tag; setting `WINGLET_VERIFY_SAVE_IMAGE` also preserves the verified image so a following scan can inspect that same local image. A requested image tag already present locally is rejected instead of replaced. Logs, `summary.json`, response bodies, and captured security headers are written under `.verification/php85/` by default; set `WINGLET_VERIFY_ARTIFACT_DIR` to choose another artifact directory. CI sets `WINGLET_VERIFY_IMAGE` to choose its build tag and `WINGLET_VERIFY_SAVE_IMAGE` to export the image tar used by the publish step.

Bitbucket default, pull-request, main, and version-tag pipelines call this same verifier in a Docker-enabled step (Docker service memory: 3072 MB). Main and version-tag steps then call `scripts/scan-security.sh` with the exact image reference just built, before exporting it to `image.tar`. They retain `.verification/security/` as an artifact and publish the tar only after the scan succeeds. The verifier uses `--pull` but not `--no-cache`; run a separate clean build when that acceptance gate is required:

```sh
docker build --pull --no-cache --platform linux/amd64 \
  --tag "wingletbase:php85-clean-acceptance-$(date +%s)-$$" .
```

### Repeatable security scan

Run the same scanner locally after building the image. The argument must name an image present in the local Docker daemon; the script rejects a missing image rather than silently scanning a registry tag or an unrelated tar file:

```sh
./scripts/scan-security.sh wingletbase:your-unique-tag
```

The default is informational: a successful scan returns 0 even when findings exist. Set `FAIL_ON_FINDINGS=1` to enforce the CI policy. `SCAN_SEVERITY` configures reported severities and defaults to `HIGH,CRITICAL`; it must include CRITICAL so the fixed release policy cannot be weakened. Release enforcement is intentionally fixed at **fixable CRITICAL** vulnerabilities, matching the prior gate's CRITICAL threshold and its ignore-unfixed behavior. HIGH findings, including fixable HIGH findings, are reported for review and do not block release. Trivy's `--ignore-unfixed` is not used, so unfixable findings remain visible. Reports are written to `.verification/security/report.txt`, `report.json`, and `summary.json`; override the report directory with `SECURITY_REPORT_DIR`. Scanner execution errors return 3, and CI policy findings with `FAIL_ON_FINDINGS=1` return 4; invalid arguments/environment or unavailable Docker/image prerequisites return 2.

The scanner uses the pinned `aquasec/trivy:0.76.0` container. Update the version only through a reviewed change: check the upstream Trivy release and image availability, validate it against the Bitbucket Docker service and this policy, then update the script and this guide together. Avoid floating tags such as `latest` so scans do not change behavior without a source change.

To avoid Docker mounts and socket access, the script copies an image archive into the pinned Trivy container and scans it with Trivy's `--input` option. For Bitbucket main/tag builds, `WINGLET_VERIFY_SAVE_IMAGE` makes it scan the exact `image.tar` artifact that the later publish step loads; local runs without that setting export the named local image with `docker save`. The scanner does not resolve a registry tag or pull another target image in its place. Trivy emits one JSON result, from which the script creates the detailed text report and policy summary. Host-owned temporary files are replaced only after JSON parsing and report generation succeed. The scanner container has an ephemeral vulnerability database cache, so each invocation may download the database; no host cache directory or Docker socket is mounted. Bitbucket main/tag build steps scan in the same step that created the image, then stop before the existing push step on scanner errors or policy failure. Default and pull-request pipelines do not scan images.

The earlier acceptance-prep task did not run the Trivy scan. For this follow-up, the local `.verification/security/report.json` supplied with the repository was read directly: the 2.33 MB Trivy 0.76.0 report for Debian 12.15 lists HIGH=315, CRITICAL=8, and fixable CRITICAL=0. It contains 239 distinct HIGH CVE IDs and 7 distinct CRITICAL CVE IDs; the repeated `CVE-2023-45853` record appears against both `zlib1g` and `zlib1g-dev`. All 323 HIGH/CRITICAL records have no Trivy `FixedVersion`. This is analysis of the provided artifact, not a new image scan. See [php85-trivy-findings.md](php85-trivy-findings.md) for all eight CRITICAL package records, status, preconditions, HIGH grouping, and package-mapping caveats. Verify the exact pipeline behavior in Bitbucket and rescan the exact release image before release.

## Reported prior runtime and Core results (2026-10-22)

The task handoff reports that the user's local `./scripts/verify-php85.sh` passed using a cached `linux/amd64` build: PHP 8.5.12, required extensions, Composer 2.10.3, PHP security settings, Apache configuration syntax, and an isolated PHP fixture returning HTTP 200 with `Server: Apache` and no `X-Powered-By`. This is a reported prior result, not a run performed in this task. Because that build used cache, it does not establish a clean `--no-cache` build.

The handoff also reports that Core PHPStan checked 165 files and PHPUnit passed 158 tests / 600 assertions on host PHP 8.5.9. Core is a separate repository and was neither inspected nor modified for this Base-only task; these are recorded as reported results, not independently verified here.

The cron/process lifecycle, runtime fixture ownership/idempotence checks, a clean no-cache image build, this task's Bitbucket CI run, and a new Trivy image scan have not been run. The existing local Trivy JSON was analyzed as an artifact only. The bounded normal-test catalog exposes only the Docker-backed verifier, which requires a separate host-permissions gate; this task did not run Docker through Bridge. Do not treat the reported cached verifier pass as evidence for these outstanding checks.

# Winglet.PHP Base

Winglet.PHP Base is a Docker image that provides the Apache and PHP runtime used by [Winglet.PHP Core](https://github.com/WingletPlatform/core). Base supplies the runtime; Core is the PHP framework/library and an application built with Core supplies its own application code and configuration. Base is not a complete Winglet.NET service or a standalone business application.

## Image

The published image is [`akikettu/wingletbase`](https://hub.docker.com/r/akikettu/wingletbase). The Dockerfile currently builds from `php:8.5.13-apache-bookworm`; this describes the checked-in configuration and may change in later revisions.

Release tags use the form `vMAJOR.MINOR.PATCH` with an optional prerelease suffix. For example, `v0.4.0-RC2` illustrates the format only; check Docker Hub for tags that are actually available.

Pull an available version:

```sh
docker pull akikettu/wingletbase:<version>
```

Replace `<version>` with a tag listed on Docker Hub; the example is a placeholder.

Build the image from this checkout:

```sh
docker build -t wingletbase:local .
```

## Included runtime

- Apache HTTP Server with `rewrite` and `remoteip` modules, and PHP 8.5 from the configured base image.
- PHP extensions: `pdo_mysql`, `fileinfo`, `gd`, `zip`, and APCu.
- Composer, cron, and the `start-services` entrypoint. The default command starts cron and then runs Apache in the foreground.
- PHP settings that disable session upload progress and `expose_php`; Apache settings hide its version and signature. PHP production configuration is enabled by the Dockerfile.
- Runtime directories under `/var/www/cache`, `/var/www/logs`, and `/var/www/var`. Startup normalizes them for shared writes by `www-data` and processes using the provided `umask 0002` scripts.
- CLI wrappers `winglet` and `winglet-doctrine`, which call the corresponding Winglet Core scripts under `/var/www/App/vendor/winglet/core`.
- Development helpers `dev-start-services` and `dev-clear`. `dev-start-services` runs `composer install` and builds routes before starting cron and Apache; use it only in an appropriate development setup. The `dev-composer-install` script is also present, but currently only prints a placeholder message.

## Running an application

The image expects a Winglet Core application, including its installed Composer dependencies, at `/var/www/App`. The bundled document root is `/var/www/html`, and its entrypoint loads `/var/www/App/vendor/autoload.php`. Provide the application files and its own required configuration when deploying. The image does not provide a ready-made application or application-specific secrets/configuration.

The default container command exposes Apache on container port `80`; publish that port through your container runtime or orchestrator. For local development, use a development-specific configuration and the `dev-start-services` helper as appropriate. Do not treat a development bind mount or development startup flow as a production deployment recipe.

The CLI helpers can be invoked in a running container, for example:

```sh
docker exec <container> winglet routes:build
docker exec <container> winglet-doctrine migrations:migrate
```

## Configuration and runtime paths

The image defines no application environment variables. Application configuration belongs to the mounted or copied application under `/var/www/App`; keep credentials outside source control and provide them through your deployment environment. The container working directory is `/var/www`.

Writable runtime data is kept at `/var/www/cache`, `/var/www/logs`, and `/var/www/var` (including Doctrine cache and proxy directories). See [`docs/runtime-paths.md`](docs/runtime-paths.md) for ownership, permissions, and cron guidance. Apache and PHP configuration included in the image is under `apache/` and `php/` in this repository.

Apache's `remoteip` configuration reads client addresses from `X-Forwarded-For` for proxies in `172.0.0.0/8`. Review that trusted-proxy range against your network topology before deployment.

## Build and verification

The verification script builds a Linux `amd64` image and checks the PHP CLI and Apache runtime, required extensions, selected PHP hardening settings, Composer, Apache configuration and HTTP behavior, cron startup, runtime-directory permissions, and graceful shutdown. It requires Bash, Docker with a working daemon, and the host tools checked by the script, including `curl`.

```sh
WINGLET_VERIFY_IMAGE=wingletbase:verify KEEP_IMAGE=1 ./scripts/verify-php85.sh
```

Verification logs and summaries are written to `.verification/php85/`. To scan that exact locally built image, Docker and Python 3 are required; the script runs the pinned Trivy container and writes text, JSON, and summary reports under `.verification/security/`:

```sh
FAIL_ON_FINDINGS=1 ./scripts/scan-security.sh wingletbase:verify
```

The scanner reports HIGH and CRITICAL findings by default. With `FAIL_ON_FINDINGS=1`, the release gate fails on **fixable CRITICAL vulnerabilities**. It does not fail on every HIGH or CRITICAL finding and does not establish that an image is vulnerability-free.

## CI and image releases

GitHub Actions runs on pushes to branches and `v*` tags, and on pull requests. It lints the Dockerfile, builds and verifies the image, and uploads available verification reports. On pushes to `main` and version tags it also runs the security scan with the release gate enabled.

A valid `v*` tag push can publish the already verified image to Docker Hub after all earlier checks pass. The workflow checks that the tag is unused and refuses to replace an existing Docker Hub version tag. It publishes only the version tag; it does not update `latest`. Publishing uses the `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` GitHub secrets. A Docker Hub image tag is separate from a GitHub Release; this workflow does not create a GitHub Release.

## Related projects

- [Winglet.PHP Base source](https://github.com/WingletPlatform/php-base)
- [Winglet.PHP Core](https://github.com/WingletPlatform/core)
- [Winglet.PHP Base on Docker Hub](https://hub.docker.com/r/akikettu/wingletbase)

No `LICENSE` file is present in this repository. Check with the project maintainers for licensing information.

# `linux-libc-dev` in the PHP 8.5.12 Base image

## Summary

The current Dockerfile does not install `linux-libc-dev` by name. The package is a transitive APT dependency of the explicitly installed development packages: `zlib1g-dev` depends on `libc6-dev`, and Bookworm `libc6-dev` depends on `linux-libc-dev`. The local Trivy findings report also lists `linux-libc-dev` 6.1.190-1 as installed in the scanned image.

This is a build-time dependency for compiling native PHP extensions, rather than an application runtime library. The Dockerfile compiles `pdo_mysql`, `fileinfo`, `gd`, and `zip`, and installs PECL APCu. The `*-dev` packages and `linux-libc-dev` remain in the final image because they are installed and used in the same image stage; deleting APT lists at line 18 does not remove packages. The headers are not required to execute already-built PHP extensions, but removing only `linux-libc-dev` would violate the declared dependency of `libc6-dev`.

## Source evidence

Relevant current Dockerfile lines:

- Lines 9–17 install `unzip`, `tzdata`, `cron`, `curl`, `ca-certificates`, `zlib1g-dev`, `libzip-dev`, and `libpng-dev`. `linux-libc-dev` is not named in this list.
- Line 18 removes `/var/lib/apt/lists/*`; it does not purge installed packages.
- Line 19 builds `pdo_mysql`, `fileinfo`, `gd`, and `zip` with `docker-php-ext-install`.
- Lines 21–22 install and enable PECL APCu, which also compiles a native extension.
- Lines 35–39 install Composer. This is separate from the libc development-header dependency and should be preserved.
- Lines 41–64 copy the PHP/Apache configuration and scripts and retain the combined Apache plus cron startup (`CMD ["start-services"]`).

Debian Bookworm's package metadata lists `libc6-dev` as a dependency of `zlib1g-dev`, and `linux-libc-dev` as a dependency of `libc6-dev` ([`zlib1g-dev`](https://packages.debian.org/bookworm/zlib1g-dev), [`libc6-dev`](https://packages.debian.org/bookworm/amd64/libc6-dev)). That dependency path explains why the Dockerfile's explicit development-package install brings in `linux-libc-dev`. The report at `docs/php85-trivy-findings.md` records the installed version and the scan's kernel-header package findings.

## Assessment and decision

No Dockerfile change is justified from this source-only investigation. `linux-libc-dev` is not an application runtime dependency, but it is pulled in for native extension builds and retained by the current single-stage image. Purging just this package would leave `libc6-dev` with an unsatisfied package dependency. A coherent removal would need to remove the development toolchain and extension `*-dev` packages after compilation, or move extension compilation to a build stage and copy the resulting extensions into a runtime stage. Either approach changes image construction and needs an image build plus the existing PHP/Apache/cron/Composer smoke checks before it is safe to adopt.

The handoff reports a previous local Trivy scan and PHP 8.5 verification, but those are not newly run or independently confirmed here. No Docker command was run in this task. The precise APT installation history of the scanned image (whether the package was already present in the upstream base or first selected by this Dockerfile's APT transaction) cannot be proven without inspecting that built image's package state/history. The dependency chain above establishes that the current Dockerfile's package set requires it even when it is not present in the base.

## Host validation commands

Run these on a host with Docker and the current repository checkout to confirm the current package state and extension availability before evaluating a cleanup:

```sh
docker build --pull --platform linux/amd64 -t winglet/base:linux-libc-dev-check .
docker run --rm --entrypoint sh winglet/base:linux-libc-dev-check -ec '
  dpkg-query -W linux-libc-dev libc6-dev zlib1g-dev libzip-dev libpng-dev;
  apt-cache depends libc6-dev;
  php -m
'
```

For any proposed purge or multi-stage change, build that candidate separately, then run `scripts/verify-php85.sh` against it (using the verifier's documented image override) and confirm the final package list, PHP extensions, Composer, Apache, cron, and runtime behavior. Scan that exact candidate image after the smoke checks. Do not treat the earlier scan as evidence for a changed image.

## Changes and verification

- Changed only this report; no Dockerfile, package, image, Composer, Apache, cron, or framework behavior was changed.
- Inspected the current Dockerfile, package references, image verification/scanning scripts, and existing scan analysis.
- Docker build, package inspection inside a built container, runtime verification, and a new image scan were not run in Bridge. The prior local results above are attributed to the handoff and existing repository report, not claimed as this task's verification.
- No archive was created; the available existing ZIP files predate this investigation and were left untouched.

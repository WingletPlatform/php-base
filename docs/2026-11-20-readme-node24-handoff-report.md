# README and GitHub Actions Node.js 24 handoff report

Date: 2026-11-20
Repository: `WingletPlatform/php-base`
Handoff: `Winglet-PHP-Base-README-Codex-CLI-handoff.md`

## Summary

Added an English README based on the checked-in Dockerfile, scripts, Apache/PHP configuration, and CI workflow. Updated the two JavaScript actions in the workflow to stable Node.js 24 versions. No runtime, Dockerfile, release, scanner, secret, or publication behavior was changed. No Git tag, GitHub Release, image push, or commit was created.

## Changes

- `README.md`
  - Explains the Base runtime and its relationship to Winglet.PHP Core.
  - Documents the current PHP base image, actual extensions and helpers, expected application location, writable runtime paths, proxy trust configuration, verification and scan commands, CI gates, and image publishing behavior.
  - Describes `v0.4.0-RC2` only as a tag-format example, not as a currently published image tag.
  - Does not state a license because this checkout has no `LICENSE` file.
- `.github/workflows/ci.yml`
  - Updated `actions/checkout@v4` to `actions/checkout@v7`.
  - Updated `actions/upload-artifact@v4` to `actions/upload-artifact@v7`.
  - Kept all inputs, conditions, and workflow logic intact. The upstream action metadata confirms both use `node24`; checkout v7 accepts the existing `ref` input, and upload-artifact v7 accepts the existing artifact inputs.
- `docs/2026-11-20-readme-node24-handoff-report.md`
  - Records this execution and verification results.

Official references reviewed:

- [GitHub Actions Node 20 retirement notice](https://github.blog/changelog/2026-09-23-node-20-is-no-longer-available-in-github-actions/)
- [actions/checkout releases](https://github.com/actions/checkout/releases)
- [actions/checkout v7 action metadata](https://raw.githubusercontent.com/actions/checkout/v7/action.yml)
- [actions/upload-artifact releases](https://github.com/actions/upload-artifact/releases)
- [actions/upload-artifact v7 action metadata](https://raw.githubusercontent.com/actions/upload-artifact/v7/action.yml)

## Verification

| Check | Result |
| --- | --- |
| `git diff --check` | Passed (exit 0). Git printed CRLF conversion warnings for unchanged tracked files. |
| `bash -n scripts/verify-php85.sh scripts/scan-security.sh` | Passed (exit 0). |
| `actionlint .github/workflows/ci.yml` | Not run; `actionlint` is not installed. |
| YAML parser | Not run; neither Ruby nor Python YAML support is available in the environment. Workflow source and upstream action input metadata were reviewed. |
| `docker version` | Docker client is installed, but access to `/var/run/docker.sock` was denied. |
| Docker build, `./scripts/verify-php85.sh`, and Trivy scan | Not run because the Docker daemon is inaccessible. |
| GitHub Actions and Docker Hub | Not run. No publication was attempted. |

The local repository has no Git tags. The attempt to query remote Git tags failed because the SSH configuration file permissions were rejected in this environment, so the README directs readers to Docker Hub to check which tags are currently available.

## Working-tree status

The starting working tree was clean on `main`, tracking `origin/main`. The final working tree contains the README, workflow update, and this report. No pre-existing user changes were present or overwritten.

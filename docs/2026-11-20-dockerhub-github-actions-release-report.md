# Docker Hub GitHub Actions handoff report

Date: 2026-11-20
Repository: `WingletPlatform/php-base`
Handoff: `Winglet-PHP-Base-DockerHub-GitHub-Actions-Codex-CLI-handoff.md`

## Summary

Restored Docker Hub image publication to `.github/workflows/ci.yml` for valid `v*` tag pushes. Publication is in the existing verification job and uses the locally built image that passed the Dockerfile lint, PHP runtime/HTTP verification, and strict Trivy scan. No build or scan policy was weakened. No Docker Hub push, Git tag, GitHub Release, or commit was created in this task.

## Changes

- `.github/workflows/ci.yml`
  - Checks out the event's immutable `github.sha`, which is also used in the local verification image name.
  - Validates version tags using `vMAJOR.MINOR.PATCH` with an optional prerelease suffix, including `v0.4.0-RC2`. Invalid `v*` tags fail before Docker Hub authentication.
  - Serializes workflow runs for the same Git ref and checks the Docker Hub repository and tag before login. Existing tags and API errors fail closed, preventing routine reruns from overwriting an existing release tag.
  - Uses the pinned `docker/login-action@v3.4.0` with repository secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.
  - After the existing verification and scan steps, tags only `akikettu/wingletbase:${GITHUB_REF_NAME}`, compares its local image ID with the verified image ID, then pushes it. No `latest` or other alias is created.
  - Keeps verification artifact upload enabled with `if: always()`.
- Added this report. No Dockerfile, PHP, runtime, API, or scanner files were changed.

The repository was clean at the start on commit `ea07c48` (`main`, matching `origin/main`). No `AGENTS.md` file or `bitbucket-pipelines.yml` is present in this checkout; existing documentation contains historical Bitbucket references only.

## Verification

| Check | Result |
| --- | --- |
| `git diff --check` | Passed, exit 0. Git emitted line-ending warnings for unchanged repository files. |
| `bash -n scripts/verify-php85.sh scripts/scan-security.sh` | Passed, exit 0. |
| Release-tag regex cases | Passed: accepts `v0.4.0-RC2` and `v1.2.3`; rejects malformed tags including `v01.2.3`, `v1.2`, `v1.2.3/evil`, and `latest`. |
| Event/ref condition review | PRs and branch pushes, including `main`, do not satisfy the publish condition. Only `push` refs under `refs/tags/v` reach the version-tag path; failed earlier steps prevent subsequent publish steps. The existing strict scanner step still runs for version-tag pushes. |
| Docker daemon | Not available: `docker version` reported client 29.10.0, but access to `/var/run/docker.sock` was denied (exit 1). |
| Hadolint, Docker image build/runtime verifier, and Trivy scan | Not run because Docker daemon access is unavailable. |
| `actionlint` / YAML parser | Not available (`actionlint` absent; Python `yaml` module absent). Workflow syntax was reviewed from source, not machine-validated. |
| GitHub Actions / Docker Hub execution | Not run. No tag was created and no image was pushed. |

## Security and publication controls

- Workflow permissions remain `contents: read`; no GitHub PAT is used.
- Docker Hub credentials are referenced only through the two repository secrets and are not printed by workflow commands.
- The login and push steps are limited to version-tag push events. The Docker Hub repository/tag preflight runs before login, rejects an existing tag, and fails closed on unexpected HTTP responses.
- The workflow serializes runs for each Git ref. As with any separate registry preflight and push, an actor publishing the same tag concurrently outside this workflow could race the check; keep Docker Hub write access limited to the release process.
- The scan remains mandatory on version-tag pushes; a failed scan stops the job before the publish steps.

## Remaining manual steps

1. Add repository secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` in GitHub. The token needs Docker Hub Repo Read & Write scope and no delete scope.
2. Review and merge the workflow change to `main`.
3. Create and push a new valid version tag from the accepted commit. The tag must not already exist in Docker Hub.
4. Confirm the tag workflow succeeds and verify `akikettu/wingletbase:<tag>` in Docker Hub. This report does not claim that a GitHub Actions run or Docker Hub publication has been tested.

## Working-tree status

No commit was created. The workflow and this report are the task changes; the initial working tree was clean.

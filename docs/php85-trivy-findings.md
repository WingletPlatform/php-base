# PHP 8.5 Base Trivy findings (2026-10-22)

## Scope and result

This analysis reads the local `.verification/security/report.json` generated for image `winglet-base-php85-clean-test`. It is Trivy JSON schema 2 from Trivy 0.76.0, scanning Debian 12.15 OS packages with severity `HIGH,CRITICAL`. The report is 2,328,398 bytes; it is not copied into this document. Trivy listed 196 OS packages and no language-package findings.

| Severity | Finding records | Unique CVE IDs | Records with `FixedVersion` |
| --- | ---: | ---: | ---: |
| CRITICAL | 8 | 7 | 0 |
| HIGH | 315 | 239 | 0 |

These are scanner records, not counts of independently exploitable paths. A single CVE may be attached to more than one binary package, and a package-level match does not establish that the vulnerable code is reachable in this image or deployment. Every record has an absent/empty Trivy `FixedVersion`, so this scan reports **zero fixable CRITICAL** and **zero fixable HIGH**. Absence of a `FixedVersion` means this report's Trivy database supplied none; it does not prove that no upstream or Debian fix exists.

## All CRITICAL records

All eight rows are Debian OS package matches (`Type=debian`, target `debian 12.15`), not Composer or other language dependencies. The versions and status below are copied from the report. `—` means Trivy did not provide a fixed version.

| CVE | Package and installed version | Fixed version | Trivy status | Issue and relevant precondition |
| --- | --- | --- | --- | --- |
| CVE-2025-7458 | `libsqlite3-0` 3.40.1-2+deb12u2 | — | `affected` | SQLite integer overflow can disclose process memory or cause denial of service. The description requires an attacker able to execute SQL, with a crafted `SELECT` containing many `ORDER BY` expressions. Ordinary parameterized application queries do not by themselves establish this precondition. [Debian tracker](https://security-tracker.debian.org/tracker/CVE-2025-7458) |
| CVE-2026-6653 | `libxml2` 2.9.14+dfsg-1.3~deb12u6 | — | `fix_deferred` | Use-after-free can cause denial of service while parsing malicious XML with improper entity-resolution handling. Exploitation requires attacker-controlled XML to reach the affected parser path. Debian marks the Bookworm issue postponed; the tracker describes a fix in upstream libxml2 2.11.0. [Debian tracker](https://security-tracker.debian.org/tracker/CVE-2026-6653) |
| CVE-2026-90037 | `linux-libc-dev` 6.1.190-1 | — | `affected` | Kernel NFS server (`nfsd`) client use-after-free during close-LRU reaping. Requires the affected kernel code and concurrent NFSv4 client expiration/reaping; it is a running-kernel issue, not code supplied by the headers package itself. [Debian tracker](https://security-tracker.debian.org/tracker/CVE-2026-90037) |
| CVE-2026-93221 | `linux-libc-dev` 6.1.190-1 | — | `affected` | Kernel NFSv4 grace/reclaim race can corrupt a list and double-free reclaim records. It requires the affected NFS server recovery/client-tracking paths to run concurrently. `linux-libc-dev` is a headers package and does not select the host kernel. [Debian tracker](https://security-tracker.debian.org/tracker/CVE-2026-93221) |
| CVE-2026-98725 | `linux-libc-dev` 6.1.190-1 | — | `affected` | Out-of-bounds write in kernel NVMe target authentication. The vulnerable path requires an active `nvmet` target receiving a short authentication response. A container's headers package does not mean that its host has enabled the affected NVMe target module. [Debian tracker](https://security-tracker.debian.org/tracker/CVE-2026-98725) |
| CVE-2026-98805 | `linux-libc-dev` 6.1.190-1 | — | `affected` | TIPC AES-GCM nonce reuse can expose confidentiality and enable forged packets. The described path requires TIPC encrypted peer traffic and a peer key-status change while the same transmit key remains installed. This is a running-kernel/configuration issue, not a userspace library in the image. [Debian tracker](https://security-tracker.debian.org/tracker/CVE-2026-98805) |
| CVE-2023-45853 | `zlib1g` 1:1.2.13.dfsg-1 | — | `will_not_fix` | The affected MiniZip API can overflow while writing ZIP entries with a long filename, comment, or extra field. The CVE description explicitly distinguishes MiniZip from supported zlib. This is one record for the runtime package. [Debian tracker](https://security-tracker.debian.org/tracker/CVE-2023-45853) |
| CVE-2023-45853 | `zlib1g-dev` 1:1.2.13.dfsg-1 | — | `will_not_fix` | Same CVE and installed source version as the preceding row, attached to the development package. Counted as a second package finding, not a second distinct CVE. Debian's Bookworm tracker says MiniZip is not built/provided from this source package in Bookworm, so this match merits package-level validation rather than assuming vulnerable MiniZip code is present. [Debian tracker](https://security-tracker.debian.org/tracker/CVE-2023-45853) |

Trivy `status` values are vulnerability-database match states, not exploitability conclusions. In particular, `fix_deferred` and `will_not_fix` still have no `FixedVersion` here and still count in the severity totals. For `CVE-2023-45853`, Trivy emits two package rows for one CVE; Debian's Bookworm note that MiniZip is not built from this source is evidence that those package associations may overstate the affected code present.

## HIGH findings by package family

The 315 HIGH records all have no Trivy `FixedVersion`. The following groups account for the records; package names are grouped where one vulnerability is surfaced against related binary packages.

| Package family | HIGH records | Fixable / not fixable in this report | Interpretation |
| --- | ---: | ---: | --- |
| `linux-libc-dev` | 205 | 0 / 205 | Kernel CVE metadata attached to headers; mostly kernel subsystem defects. Image presence does not imply that those kernel subsystems run inside the container. The host kernel and enabled features determine exposure. |
| Apache (`apache2`, `apache2-bin`, `apache2-data`, `apache2-utils`) | 28 | 0 / 28 | Seven CVE records per related binary package. Treat package rows as repeated package matches, not 28 separate Apache CVEs; validate package-level Debian security status and the actual Apache code paths. |
| util-linux (`bsdutils`, `libblkid1`, `libmount1`, `libsmartcols1`, `libuuid1`, `mount`, `util-linux`, `util-linux-extra`) | 48 | 0 / 48 | Six records on each of eight related packages, often reflecting shared source/components. Reachability depends on which command/library is invoked and whether an attacker can supply the affected input or exercise the local privileged path. |
| `curl`, `libcurl4` | 10 | 0 / 10 | Five records on each related package. Exposure depends on use of affected libcurl behavior and attacker control of relevant protocol/server input. |
| `libxml2` | 6 | 0 / 6 | XML parser and utility findings; require input to reach the particular parser or utility code path. |
| `libsqlite3-0` | 2 | 0 / 2 | SQL engine findings; relevant if attacker-controlled SQL reaches the affected functionality. |
| Other packages | 16 | 0 / 16 | One record each across `gzip`, `libacl1`, `libexpat1`, `libldap-2.5-0`, `libncursesw6`, `libperl5.36`, `libssl3`, `libsystemd0`, `libtinfo6`, `libudev1`, `ncurses-base`, `ncurses-bin`, `openssl`, `perl`, `perl-base`, and `perl-modules-5.36`. Review the individual report rows before prioritizing these. |

The report contains 239 distinct HIGH CVE IDs across 315 rows. Package families and duplicate matches explain why the row count is larger than the distinct-CVE count. The top concentration is `linux-libc-dev` (205/315, about 65%); it should be triaged as kernel/host exposure and package mapping rather than interpreted as 205 application-library vulnerabilities.

## Policy and practical follow-up

`FAIL_ON_FINDINGS=1` blocks only when Trivy reports a CRITICAL record with a nonempty `FixedVersion`. It does not block on every CRITICAL or any HIGH finding. This preserves the previous release gate's effective `--ignore-unfixed --severity CRITICAL` behavior while allowing the report to show unfixed issues. Therefore these 8 CRITICAL records do not fail the gate: none has a Trivy fix version. Main and version-tag Bitbucket pipelines enable this policy; the default and pull-request pipelines do not run the security scan.

Practical next steps justified by this report:

1. Refresh the PHP base image and Debian package metadata/packages in a reviewed build, then rescan. The Dockerfile runs `apt-get update` before installing its direct packages but does not explicitly upgrade all packages inherited from the base image; a refreshed upstream image or deliberate package-upgrade step may change stale inherited versions. Verify the resulting package versions and regression behavior before keeping such a change.
2. Check whether `linux-libc-dev` is needed in the final runtime image after PHP extensions are built. If it is only a build-time dependency, removing it from the final layer or using a build/runtime split can reduce irrelevant header-package findings; this does not remediate the host kernel and must be confirmed against the image build.
3. For SQLite and libxml2, trace whether the application accepts attacker-controlled SQL/XML and whether the vulnerable API path is reachable. For zlib, confirm whether any MiniZip implementation is present or used; Debian's Bookworm tracking notes suggest the reported zlib association is not sufficient evidence that MiniZip is shipped.
4. Review Debian package tracker entries and Trivy's database for discrepancies before deciding that an absent `FixedVersion` means no fix is available. Re-scan the exact release image after any package update.

The supplied JSON does not prove exploitability, running-kernel version/configuration, application reachability, or whether a vulnerable code path is enabled. The preconditions above summarize each issue's description and should be treated as triage guidance, not proof of safety. The report used local repository evidence; the Debian tracker links provide issue-specific package notes where available.

## Implementation and verification

- `scripts/scan-security.sh` now captures Trivy stdout in host-owned temporary files, parses the JSON and writes/appends the summary before replacing report files. It uses strict shell error handling and returns nonzero for scanner failures, empty or invalid JSON, summary failures, report append/replacement failures, and the configured CI policy failure. The Docker socket remains read-only; no socket access assumption was changed.
- `docs/php85-migration.md` records the exact CI policy, report ownership behavior, and this local artifact's result. The existing working-tree Bitbucket pipeline already invokes the scan in main and version-tag steps with `FAIL_ON_FINDINGS=1`; that file was inspected and left untouched by this task.
- Local verification: `bash -n scripts/scan-security.sh` passed; the supplied JSON parsed and reproduced HIGH=315, CRITICAL=8, 239 distinct HIGH CVEs, 7 distinct CRITICAL CVEs, and zero records with `FixedVersion`. No new image scan or Docker build was run. The only bounded normal test is the Docker-backed PHP 8.5 verifier and it requires host permissions, so it was not run.
- A changed-files-only ZIP was not created because no bounded archive tool is available in this task. Existing ZIP files in the worktree were left untouched.

Files changed for this task: `scripts/scan-security.sh`, `docs/php85-migration.md`, and this report. No `.verification` artifacts were modified.

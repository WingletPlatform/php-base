#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for tool in docker curl mktemp tee cat date sleep id; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Required tool is missing: %s\n' "$tool" >&2
        exit 2
    fi
done

ARTIFACT_DIR="${WINGLET_VERIFY_ARTIFACT_DIR:-$ROOT_DIR/.verification/php85}"
mkdir -p "$ARTIFACT_DIR"
LOG_FILE="$ARTIFACT_DIR/verify.log"
SUMMARY_FILE="$ARTIFACT_DIR/summary.json"
exec > >(tee "$LOG_FILE") 2>&1

suffix="$(date +%s)-$$-${RANDOM}"
image="${WINGLET_VERIFY_IMAGE:-winglet-base-php85-verify:$suffix}"
container="winglet-base-php85-verify-$suffix"
fixture_dir=''
runtime_dir=''
save_image="${WINGLET_VERIFY_SAVE_IMAGE:-}"
keep_image="${KEEP_IMAGE:-}"
image_created=0
container_created=0
if [[ -n "$keep_image" && "$keep_image" != '1' ]]; then
    printf 'KEEP_IMAGE must be unset or 1; actual value: %q\n' "$keep_image" >&2
    exit 2
fi
cleanup() {
    if [[ "$container_created" -eq 1 ]]; then
        docker rm -f "$container" >/dev/null 2>&1 || true
    fi
    if [[ "$image_created" -eq 1 ]] && docker image inspect "$image" >/dev/null 2>&1; then
        if [[ "$keep_image" == '1' || -n "$save_image" ]]; then
            printf 'Preserved verification image: %s\n' "$image"
        else
            docker image rm "$image" >/dev/null 2>&1 || true
        fi
    fi
    if [[ -n "$fixture_dir" ]]; then
        rm -rf -- "$fixture_dir"
    fi
}
published_port() {
    local container_name="$1"
    local port=''
    local attempt

    # Docker can report the container as started just before the dynamic host
    # port is visible in its network settings. Retry metadata lookup rather
    # than relying on `docker port`, which exits nonzero during that window.
    for attempt in {1..10}; do
        port="$(docker inspect --format '{{with (index .NetworkSettings.Ports "80/tcp")}}{{(index . 0).HostPort}}{{end}}' "$container_name" 2>/dev/null || true)"
        if [[ "$port" =~ ^[0-9]+$ ]]; then
            printf '%s\n' "$port"
            return 0
        fi
        sleep 1
    done

    printf 'Could not find a published loopback port for container %s (expected 127.0.0.1:<port> -> 80/tcp)\n' \
        "$container_name" >&2
    docker inspect --format 'Container state={{.State.Status}} ports={{json .NetworkSettings.Ports}}' \
        "$container_name" >&2 || true
    docker logs "$container_name" >&2 || true
    return 1
}
diagnose_http_failure() {
    local container_name="$1"
    local url="$2"
    printf 'HTTP readiness failed for %s after bounded retries: %s\n' "$container_name" "$url" >&2
    docker inspect --format 'Container state={{.State.Status}} exit={{.State.ExitCode}} ports={{json .NetworkSettings.Ports}}' \
        "$container_name" >&2 || true
    docker logs "$container_name" >&2 || true
}
current_step='preparing disposable fixture'
on_exit() {
    status=$?
    if [[ "$status" -ne 0 ]]; then
        printf '{"status":"failed","exit_code":%s,"failed_step":"%s","minimum_php":"8.5.12","image":"%s"}\n' \
            "$status" "$current_step" "$image" > "$SUMMARY_FILE"
    fi
    cleanup
    return "$status"
}
trap on_exit EXIT
docker version --format 'Docker client={{.Client.Version}} server={{.Server.Version}}'
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/winglet-base-smoke.XXXXXXXX")"
chmod 0755 "$fixture_dir"

# Stage unique, deliberately restrictive fixture files into the disposable
# container before startup so the production normalizer must repair them.
runtime_dir="$fixture_dir/runtime"
mkdir -p \
    "$runtime_dir/cache" \
    "$runtime_dir/logs" \
    "$runtime_dir/var/cache/doctrine" \
    "$runtime_dir/var/doctrine/proxies"
printf 'runtime-permission-fixture\n' > "$runtime_dir/cache/fixture.txt"
printf 'runtime-permission-fixture\n' > "$runtime_dir/logs/fixture.txt"
printf 'runtime-permission-fixture\n' > "$runtime_dir/var/fixture.txt"
chmod 0600 "$runtime_dir/cache/fixture.txt" "$runtime_dir/logs/fixture.txt" "$runtime_dir/var/fixture.txt"

cat > "$fixture_dir/__verify_php85.php" <<'PHP'
<?php
header('Content-Type: text/plain');
echo implode('|', [
    PHP_VERSION,
    (string)ini_get('session.upload_progress.enabled'),
    (string)ini_get('expose_php'),
    (string)ini_get('display_errors'),
    (string)ini_get('log_errors'),
    (string)ini_get('memory_limit'),
    (string)ini_get('fatal_error_backtraces'),
]);
PHP
cat > "$fixture_dir/__verify_php85_error.php" <<'PHP'
<?php
http_response_code(500);
header('Content-Type: text/plain');
echo 'winglet-php85-http-error-ok';
PHP
chmod 0644 "$fixture_dir/__verify_php85.php" "$fixture_dir/__verify_php85_error.php"

printf '{"status":"running","minimum_php":"8.5.12","image":"%s"}\n' "$image" > "$SUMMARY_FILE"
if docker image inspect "$image" >/dev/null 2>&1; then
    printf 'Refusing to replace pre-existing or external image: %s\n' "$image" >&2
    exit 1
fi
current_step='Docker image build'
echo '==> Build Base image (linux/amd64)'
image_created=1
docker build --pull --platform linux/amd64 --tag "$image" .

current_step='PHP runtime, extensions, Composer, and hardening'
echo '==> Check PHP runtime and required extensions'
docker run --rm "$image" php -v
docker run --rm "$image" php -r '
$required = ["pdo_mysql", "fileinfo", "gd", "zip", "apcu"];
if (version_compare(PHP_VERSION, "8.5.12", "<")) { fwrite(STDERR, sprintf("Expected PHP >= 8.5.12, got %s\n", PHP_VERSION)); exit(1); }
foreach ($required as $extension) {
    if (!extension_loaded($extension)) { fwrite(STDERR, sprintf("Missing PHP extension: %s\n", $extension)); exit(1); }
}
$expected = [
    "session.upload_progress.enabled" => false,
    "expose_php" => false,
    "display_errors" => false,
    "log_errors" => true,
];
foreach ($expected as $key => $enabled) {
    $actual = ini_get($key);
    $normalized = strtolower(trim((string)$actual));
    $is_enabled = in_array($normalized, ["1", "on", "true", "yes"], true);
    if ($is_enabled !== $enabled) {
        $expected_value = $enabled ? "On" : "Off";
        fwrite(STDERR, sprintf("Unexpected PHP setting %s: expected %s; actual %s\n", $key, $expected_value, var_export($actual, true)));
        exit(1);
    }
}
$ini = ["memory_limit" => ini_get("memory_limit"), "fatal_error_backtraces" => ini_get("fatal_error_backtraces")];
printf("PHP runtime=%s memory_limit=%s fatal_error_backtraces=%s\n", PHP_VERSION, $ini["memory_limit"], var_export($ini["fatal_error_backtraces"], true));
echo "PHP runtime, extensions, and security settings OK", PHP_EOL;
'
docker run --rm "$image" php -m
docker run --rm "$image" composer --version --no-ansi
echo '==> Record pulled base-image and built image identities (digests are reported when available)'
# A successful BuildKit build does not guarantee that its FROM image is locally
# tagged. Report the declared Dockerfile source separately from inspect data so
# the source reference is never presented as cryptographic provenance.
base_image_reference="$(awk '$1 == "FROM" { print $2; exit }' Dockerfile)"
if [[ -z "$base_image_reference" ]]; then
    printf 'Could not read a FROM image reference from Dockerfile\n' >&2
    exit 1
fi
printf 'Dockerfile FROM reference (declared source, not verified provenance): %s\n' "$base_image_reference"
if base_image_inspect="$(docker image inspect --format 'Locally available FROM image_id={{.Id}} repo_digests={{json .RepoDigests}}' "$base_image_reference" 2>/dev/null)"; then
    printf '%s\n' "$base_image_inspect"
elif base_registry_inspect="$(docker buildx imagetools inspect "$base_image_reference" 2>/dev/null)"; then
    printf 'Registry manifest information for declared FROM reference:\n%s\n' "$base_registry_inspect"
else
    echo 'FROM image is not available for local inspect and registry digest lookup was unavailable; continuing with built-image checks.'
fi
docker image inspect --format 'Built image reference={{.RepoTags}} image_id={{.Id}} repo_digests={{json .RepoDigests}}' "$image"

current_step='Apache configuration'
echo '==> Validate Apache configuration'
docker run --rm "$image" apache2ctl configtest

current_step='Apache HTTP readiness'
echo '==> Create disposable container, stage fixtures, then start Apache'
docker create --name "$container" -p 127.0.0.1::80 "$image" >/dev/null
container_created=1
docker cp "$runtime_dir/cache/." "$container:/var/www/cache/"
docker cp "$runtime_dir/logs/." "$container:/var/www/logs/"
docker cp "$runtime_dir/var/." "$container:/var/www/var/"
docker cp "$fixture_dir/__verify_php85.php" "$container:/var/www/html/__verify_php85.php"
docker cp "$fixture_dir/__verify_php85_error.php" "$container:/var/www/html/__verify_php85_error.php"
docker start "$container" >/dev/null
cli_php_version="$(docker exec "$container" php -r 'echo PHP_VERSION;')"
if ! docker exec "$container" php -r 'exit(version_compare(PHP_VERSION, "8.5.12", "<") ? 1 : 0);'; then
    printf 'CLI PHP must be >= 8.5.12; actual version: %s\n' "$cli_php_version" >&2
    exit 1
fi
printf 'Container CLI PHP version: %s\n' "$cli_php_version"
current_step='container memory and published-port discovery'
if ! memory_constraint="$(docker inspect --format '{{.HostConfig.Memory}}' "$container")"; then
    printf 'Verification failed during %s: Docker could not inspect HostConfig.Memory for container %s.\n' \
        "$current_step" "$container" >&2
    exit 1
fi
printf 'Container memory constraint (HostConfig.Memory bytes; 0 means unlimited): %s\n' "$memory_constraint"
if ! port="$(published_port "$container")"; then
    printf 'Verification failed during %s: unable to obtain the disposable container port for 80/tcp.\n' \
        "$current_step" >&2
    exit 1
fi
printf 'Published container HTTP port: 127.0.0.1:%s -> 80/tcp\n' "$port"
url="http://127.0.0.1:$port/__verify_php85.php"
ready=0
for attempt in {1..30}; do
    if http_status="$(curl --silent --connect-timeout 2 --max-time 5 \
        --dump-header "$ARTIFACT_DIR/security-headers.txt" \
        --output "$ARTIFACT_DIR/php85-fixture.body" \
        --write-out '%{http_code}' "$url" 2>/dev/null)"; then
        ready=1
        break
    fi
    sleep 1
done
if [[ "$ready" -ne 1 ]]; then
    diagnose_http_failure "$container" "$url"
    exit 1
fi
current_step='PHP fixture HTTP response'
if [[ "$http_status" != '200' ]]; then
    printf 'PHP fixture test failed: expected HTTP 200, got %s\n' "$http_status" >&2
    exit 1
fi
if ! IFS='|' read -r http_php_version upload_progress expose_php display_errors log_errors memory_limit fatal_error_backtraces \
    < "$ARTIFACT_DIR/php85-fixture.body"; then
    # Bash read returns 1 when EOF arrives before a newline, even though it
    # populated variables from the final line. The PHP fixture intentionally
    # emits no trailing newline, so accept that complete non-empty response.
    if [[ -z "${http_php_version:-}" ]]; then
        printf 'PHP fixture response was empty or could not be parsed: %s\n' "$ARTIFACT_DIR/php85-fixture.body" >&2
        exit 1
    fi
fi
if [[ "$http_php_version" != "$cli_php_version" ]]; then
    printf 'PHP version mismatch: CLI reports %s, Apache HTTP PHP reports %s\n' "$cli_php_version" "$http_php_version" >&2
    exit 1
fi
case "${upload_progress,,}" in ''|0|off|false|no) : ;; *) upload_progress_invalid=1 ;; esac
case "${expose_php,,}" in ''|0|off|false|no) : ;; *) expose_php_invalid=1 ;; esac
case "${display_errors,,}" in ''|0|off|false|no) : ;; *) display_errors_invalid=1 ;; esac
case "${log_errors,,}" in 1|on|true|yes) : ;; *) log_errors_invalid=1 ;; esac
if [[ -n "${upload_progress_invalid:-}" || -n "${expose_php_invalid:-}" || -n "${display_errors_invalid:-}" || -n "${log_errors_invalid:-}" ]]; then
    printf 'Unexpected Apache PHP ini values: session.upload_progress.enabled=%q expose_php=%q display_errors=%q log_errors=%q\n' \
        "$upload_progress" "$expose_php" "$display_errors" "$log_errors" >&2
    exit 1
fi
printf 'Apache HTTP PHP version=%s memory_limit=%s fatal_error_backtraces=%s\n' \
    "$http_php_version" "$memory_limit" "$fatal_error_backtraces"
server_header=''
server_found=0
powered_found=0
powered_values=''
while IFS= read -r header; do
    header="${header%$'\r'}"
    header_name="${header%%:*}"
    header_value="${header#*:}"
    header_value="${header_value#"${header_value%%[![:space:]]*}"}"
    case "${header_name,,}" in
        server)
            server_found=1
            if [[ -n "$server_header" ]]; then server_header+=$'\n'; fi
            server_header+="$header_value"
            ;;
        x-powered-by)
            powered_found=1
            if [[ -n "$powered_values" ]]; then powered_values+=$'\n'; fi
            powered_values+="$header_value"
            ;;
    esac
done < "$ARTIFACT_DIR/security-headers.txt"
if [[ "$powered_found" -eq 1 ]]; then
    printf 'Unexpected HTTP header X-Powered-By: expected absent (PHP version hidden); actual %q\n' "$powered_values" >&2
    exit 1
fi
if [[ "$server_found" -ne 1 || "$server_header" != 'Apache' ]]; then
    actual_server=''
    if [[ "$server_found" -eq 1 ]]; then actual_server="$server_header"; else actual_server='<absent>'; fi
    printf 'Unexpected HTTP header Server: expected exactly Apache (ServerTokens Prod); actual %q\n' "$actual_server" >&2
    exit 1
fi
printf 'Apache and PHP fixture HTTP smoke OK (%s; Server: %s; X-Powered-By absent)\n' "$url" "$server_header"

current_step='HTTP error response and continued availability'
error_url="http://127.0.0.1:$port/__verify_php85_error.php"
error_status="$(curl --silent --connect-timeout 2 --max-time 5 \
    --output "$ARTIFACT_DIR/php85-error.body" --write-out '%{http_code}' "$error_url")"
if [[ "$error_status" != '500' || "$(cat "$ARTIFACT_DIR/php85-error.body")" != 'winglet-php85-http-error-ok' ]]; then
    printf 'HTTP error fixture failed: expected HTTP 500 with controlled body; got status=%s body=%q\n' \
        "$error_status" "$(cat "$ARTIFACT_DIR/php85-error.body")" >&2
    exit 1
fi
if ! curl --silent --connect-timeout 2 --max-time 5 --output "$ARTIFACT_DIR/php85-fixture-after-error.body" \
    --write-out '%{http_code}' "$url" > "$ARTIFACT_DIR/php85-fixture-after-error.status"; then
    printf 'Apache stopped responding after a controlled HTTP 500 response\n' >&2
    exit 1
fi
if [[ "$(cat "$ARTIFACT_DIR/php85-fixture-after-error.status")" != '200' ]]; then
    printf 'PHP fixture after HTTP error failed: expected HTTP 200, got %s\n' \
        "$(cat "$ARTIFACT_DIR/php85-fixture-after-error.status")" >&2
    exit 1
fi
echo 'HTTP 500 response returned; subsequent PHP request remained available'

current_step='cron startup and runtime directory permissions'
echo '==> Check cron startup and runtime directory ownership/modes on staged fixtures'
docker exec "$container" sh -eu -c '
found_cron=0
found_apache=0
for comm in /proc/[0-9]*/comm; do
    [ -r "$comm" ] || continue
    IFS= read -r process < "$comm" || true
    case "$process" in cron) found_cron=1 ;; apache2) found_apache=1 ;; esac
done
[ "$found_cron" -eq 1 ] || { echo "cron process is not running" >&2; exit 1; }
[ "$found_apache" -eq 1 ] || { echo "Apache process is not running" >&2; exit 1; }
php -r '\''
$paths = [
    "/var/www/cache" => ["dir", "2775"],
    "/var/www/cache/fixture.txt" => ["file", "664"],
    "/var/www/logs" => ["dir", "2775"],
    "/var/www/logs/fixture.txt" => ["file", "664"],
    "/var/www/var" => ["dir", "2775"],
    "/var/www/var/cache/doctrine" => ["dir", "2775"],
    "/var/www/var/doctrine/proxies" => ["dir", "2775"],
    "/var/www/var/fixture.txt" => ["file", "664"],
];
foreach ($paths as $path => [$type, $mode]) {
    if (($type === "dir" && !is_dir($path)) || ($type === "file" && !is_file($path))) {
        fwrite(STDERR, "Missing runtime fixture: $path\n"); exit(1);
    }
    $actual = sprintf("%d:%d:%o", fileowner($path), filegroup($path), fileperms($path) & 07777);
    $expected = "33:33:$mode";
    if ($actual !== $expected) {
        fwrite(STDERR, "Unexpected runtime permissions for $path: expected $expected, got $actual\n"); exit(1);
    }
}
echo "Cron and Apache processes are running; staged runtime permissions are correct\n";
'\''
'
# Re-running the setup command must leave the same ownership and permissions.
docker exec "$container" /usr/local/bin/setup-runtime-dirs
docker exec "$container" php -r '
$paths = ["/var/www/cache", "/var/www/logs", "/var/www/var", "/var/www/var/cache/doctrine", "/var/www/var/doctrine/proxies"];
foreach ($paths as $path) {
    if (fileowner($path) !== 33 || filegroup($path) !== 33 || (fileperms($path) & 07777) !== 02775) {
        fwrite(STDERR, "Runtime directory normalization is not idempotent at $path\n"); exit(1);
    }
}
echo "Runtime directory setup is idempotent\n";
'

current_step='container shutdown and signal handling'
echo '==> Stop the disposable container and verify graceful PID 1 exit'
docker stop --time 10 "$container" >/dev/null
state="$(docker inspect --format '{{.State.Status}}' "$container")"
exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$container")"
if [[ "$state" != 'exited' || "$exit_code" != '0' ]]; then
    printf 'Unexpected shutdown result: state=%s exit_code=%s\n' "$state" "$exit_code" >&2
    docker logs "$container" >&2 || true
    exit 1
fi
echo 'Disposable Apache/cron container stopped with exit code 0'

if [[ -n "$save_image" ]]; then
    current_step='saving verified image artifact'
    docker save --output "$save_image" "$image"
fi
current_step='complete'
printf '{"status":"passed","minimum_php":"8.5.12","platform":"linux/amd64","image":"%s","checks":["cli-and-apache-php-version-match","php-version-minimum","extensions","php-ini-hardening","production-display-and-log-errors","php-memory-and-backtrace-settings-reported","image-identities-and-available-digests-reported","container-memory-constraint-reported","composer-version","apache-config","apache-http-readiness","php-fixture-http-200","controlled-http-500-and-follow-up-request","apache-security-headers","cron-startup","runtime-fixture-ownership-and-modes","runtime-dir-idempotence","container-graceful-stop"]}\n' "$image" > "$SUMMARY_FILE"
echo "Verification passed. Log: $LOG_FILE; summary: $SUMMARY_FILE"

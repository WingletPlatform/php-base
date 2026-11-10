# Runtime paths and permissions

WingletBase keeps `/var/www/App` as static application code. Runtime data is written under `/var/www/var` instead.

## Writable runtime directories

The container creates and maintains these writable paths:

- `/var/www/cache`
- `/var/www/logs`
- `/var/www/var/cache/doctrine`
- `/var/www/var/doctrine/proxies`

All writable directories use group-writable permissions with the setgid bit:

- directories: `2775`
- files: `0664`
- owner/group: `www-data:www-data`
- default shell umask in provided scripts: `0002`

This keeps files editable regardless of whether they were created via the HTTP interface, cron jobs, or CLI commands.

## Important note for cron jobs

If a cron job writes files directly, make sure it runs with `umask 0002`.

Recommended pattern:

```sh
umask 0002; /usr/local/bin/winglet some:command
```

or

```sh
umask 0002; /usr/local/bin/winglet-doctrine migrations:migrate
```

The provided `winglet` and `winglet-doctrine` wrappers already set `umask 0002` and normalize runtime directories before execution.

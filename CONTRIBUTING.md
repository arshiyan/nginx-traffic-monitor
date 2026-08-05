# Contributing to Nginx Traffic Monitor

Thank you for contributing. This project is intentionally dependency-free
(Bash + coreutils only) and plugin-oriented.

## Development principles

1. Keep the core (`lib/`) small. Prefer a new plugin under `plugins/`.
2. Do not add Python, PHP, Node, Perl, jq, SQLite, or MySQL.
3. Stay shellcheck-friendly; quote variables; avoid `eval` except in the loader.
4. Never risk corrupting `nginx.conf` without backup + `nginx -t` + rollback.
5. Write comments on non-obvious functions.

## Adding a plugin

See [docs/PLUGINS.md](docs/PLUGINS.md).

Minimal checklist:

- [ ] `plugins/NN-name/plugin.conf` with unique `PLUGIN_ID`
- [ ] `plugins/NN-name/plugin.sh` with `plugin_run`
- [ ] Entry in `config/plugins.enabled`
- [ ] README / docs note if user-facing
- [ ] Sample data if the plugin needs fixtures

## Getting the source

```bash
git clone https://github.com/arshiyan/nginx-traffic-monitor.git
cd nginx-traffic-monitor
```

## Testing locally

```bash
# Demo without nginx using the sample log
./traffic-monitor.sh --sample --report today
./traffic-monitor.sh --sample --isp-report --period all
./traffic-monitor.sh --plugins list
```

On a real Ubuntu/Debian host:

```bash
sudo ./install.sh
sudo ./traffic-monitor.sh
```

Or install directly from GitHub in one step:

```bash
git clone https://github.com/arshiyan/nginx-traffic-monitor.git \
  && cd nginx-traffic-monitor \
  && sudo chmod +x install.sh traffic-monitor.sh \
  && sudo ./install.sh
```

## Pull requests

- Keep PRs focused (one plugin or one core fix).
- Describe the why, not only the what.
- Include before/after CLI output when relevant.

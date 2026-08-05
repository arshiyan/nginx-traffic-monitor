# Plugin Development Guide

Nginx Traffic Monitor loads every enabled directory under `plugins/` (and
`plugins/examples/`) at startup. You can extend the product without editing the core.

## Layout

```
plugins/NN-my-feature/
├── plugin.conf      # metadata
├── plugin.sh        # plugin_init / plugin_run / plugin_help
└── data/            # optional assets (CIDR, templates, …)
```

The numeric prefix (`10-`, `20-`, …) controls discovery order and pairs with
`PLUGIN_PRIORITY` for menu ordering.

## plugin.conf

```bash
PLUGIN_ID="my_feature"           # unique snake_case id
PLUGIN_NAME="My Feature"
PLUGIN_DESC="Short description"
PLUGIN_VERSION="1.0.0"
PLUGIN_MENU_LABEL="17) My Feature"
PLUGIN_CLI_FLAGS="--my-feature|--my-feature-alt"
PLUGIN_ENABLED=1
PLUGIN_REQUIRES_ROOT=0
PLUGIN_PRIORITY=55
PLUGIN_HIDE_MENU=0               # optional
```

Enable/disable at runtime:

```bash
./traffic-monitor.sh --plugins list
./traffic-monitor.sh --plugins enable my_feature
./traffic-monitor.sh --plugins disable my_feature
```

Overrides live in `config/plugins.enabled`.

## plugin.sh contract

```bash
plugin_init() {
  # optional: register hooks
  ntm_register_hook after_report my_feature_after_report
}

plugin_run() {
  # required: main action (menu + CLI)
  ntm_title "My Feature"
  ntm_info "Hello from $NTM_CURRENT_PLUGIN_DIR"
}

plugin_help() {
  echo "What this plugin does"
}
```

Available context while `plugin_run` executes:

- `NTM_CURRENT_PLUGIN_ID`
- `NTM_CURRENT_PLUGIN_DIR`
- `NTM_ROOT`, `NTM_TRAFFIC_LOG`, `NTM_CLI_PERIOD`, `NTM_CLI_OUT`, …

## Hooks

| Hook | When |
|------|------|
| `before_menu` | Before drawing the menu |
| `after_menu_select` | After a menu choice |
| `before_report` / `after_report` | Around full reports |
| `before_export` / `after_export` | Around exports |
| `on_live_tick` | Each live-monitor second |
| `on_install` / `on_uninstall` | Installer lifecycle |

Register with:

```bash
ntm_register_hook after_report my_callback
```

## Shared helpers

- `ntm_filter_log <period>` — filtered log stream
- `ntm_run_report <period>` — full analytics report
- `ntm_top_field <period> <url|ip|status|host|ext>`
- `ntm_human_bytes <n>`
- `ntm_info` / `ntm_ok` / `ntm_warn` / `ntm_error`

## Example

Enable the bundled example:

```bash
./traffic-monitor.sh --plugins enable hello_world
./traffic-monitor.sh --hello
```

Source: `plugins/examples/99-hello-world/`.

## ISP / ASN plugin as a reference

`plugins/43-isp-asn/` demonstrates:

- local `data/*.cidr` flat-file database
- `asn_match.awk` for classification
- CLI flags `--isp-report` and `--isp-update-db`
- HTML snippet integration for the export dashboard

To add another Iranian ISP, create `data/shatel.cidr` and extend the awk loader
(or generalize `asn_map.conf`) — no core changes required.

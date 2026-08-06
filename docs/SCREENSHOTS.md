# Screenshots

Demo captures committed under `docs/images/` (generated from `--sample` CLI output and the HTML export dashboard).

| File | Content |
|------|---------|
| `menu.png` | Interactive main menu |
| `report-today.png` | Today / metrics report |
| `isp-asn.png` | Irancell / MCI / Other breakdown |
| `export-html.png` | Pure HTML/CSS export dashboard |
| `live.png` | Live monitor (RPS, bandwidth, last request) |

Regenerate locally after changing sample data or export styling:

```bash
./traffic-monitor.sh --sample --report all
./traffic-monitor.sh --sample --isp-report --period all
./traffic-monitor.sh --sample --export html --period all --out /tmp/ntm-dashboard.html
# open the HTML file in a browser and capture; or re-render terminal shots for README
```

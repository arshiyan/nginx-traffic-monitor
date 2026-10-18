# Nginx Traffic Monitor

**Language / زبان:** [English](#nginx-traffic-monitor) · [فارسی](#nginx-traffic-monitor-فارسی)

Production-ready **Bash-only** Nginx traffic analytics for Ubuntu/Debian and aaPanel — install, report, live-monitor, and export with a plugin architecture and **zero extra runtimes**.

No Python · No PHP · No Node · No jq · No database — only `bash`, `awk`, `grep`, `sed`, and standard Unix tools.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian%20%7C%20aaPanel-orange)](#supported-linux-distributions)
[![Shell](https://img.shields.io/badge/runtime-Bash%20%2B%20awk-brightgreen)](#requirements)
[![GitHub stars](https://img.shields.io/github/stars/arshiyan/nginx-traffic-monitor?style=social)](https://github.com/arshiyan/nginx-traffic-monitor)
[![GitHub](https://img.shields.io/badge/repo-arshiyan%2Fnginx--traffic--monitor-24292e?logo=github)](https://github.com/arshiyan/nginx-traffic-monitor)

---

## Quick install

```bash
git clone https://github.com/arshiyan/nginx-traffic-monitor.git \
  && cd nginx-traffic-monitor \
  && sudo chmod +x install.sh traffic-monitor.sh \
  && sudo ./install.sh
```

```bash
sudo ./traffic-monitor.sh          # interactive menu
cd nginx-traffic-monitor && git pull && sudo ./install.sh --verify-only   # update
```

Demo without a live log: `./traffic-monitor.sh --sample --report all`

---

## Screenshots

| Menu | Today report | ISP / ASN |
|:----:|:------------:|:---------:|
| ![menu](docs/images/menu.png) | ![report](docs/images/report-today.png) | ![isp](docs/images/isp-asn.png) |

| HTML export | Live monitor |
|:-----------:|:------------:|
| ![html](docs/images/export-html.png) | ![live](docs/images/live.png) |

How to capture your own: [docs/SCREENSHOTS.md](docs/SCREENSHOTS.md)

---

## Project overview

Configures a dedicated `log_format traffic`, writes structured access logs, and ships an interactive menu plus a non-interactive CLI for cron.

Features live as **plugins** under [`plugins/`](plugins/). The core stays small; ISP/ASN (Irancell / MCI / Other) and more ship as drop-ins.

```
install.sh              → safe nginx wiring (backup → edit → nginx -t → reload / rollback)
traffic-monitor.sh      → menu + CLI + plugin loader
lib/                    → core engine
plugins/                → reports, live, export, ISP/ASN, …
```

---

## Features

| Area | What you get |
|------|----------------|
| Install | Auto nginx / aaPanel detection, backups, `nginx -t`, rollback |
| Reports | Today / 24h / 7d / 30d — totals, Top URLs/IPs/status/hosts/ext |
| ISP/ASN | Irancell · Hamrah-e Avval (MCI) · Other (flat CIDR files) |
| Live | RPS, bandwidth estimate, last client/URI, log growth |
| Export | TXT + pure HTML/CSS dashboard (no JS libraries) |
| Ops | Log rotate reset, verify, clean uninstall, sample log, logrotate snippet |
| Extensibility | Plugin enable/disable, hooks, CLI registration |

---

## Requirements

| Required | Purpose |
|----------|---------|
| git | clone from GitHub |
| bash | runtime |
| awk, grep, sed, cut, sort, uniq | parsing & reports |
| find, stat, tail, wc, date | filesystem & time windows |
| nginx | target web server (install/verify) |
| root | only for install / reset / uninstall |

Optional soft dependency: `curl` (only for guided ASN DB update hints).

---

## Installation

### Option A — One-liner from GitHub (recommended)

```bash
git clone https://github.com/arshiyan/nginx-traffic-monitor.git \
  && cd nginx-traffic-monitor \
  && sudo chmod +x install.sh traffic-monitor.sh \
  && sudo ./install.sh
```

### Option B — Step by step

```bash
git clone https://github.com/arshiyan/nginx-traffic-monitor.git
cd nginx-traffic-monitor
sudo chmod +x install.sh traffic-monitor.sh
sudo ./install.sh
```

What the installer does:

1. Detects the nginx binary and `nginx.conf`
2. Backs up the config under `/var/backups/nginx-traffic-monitor/`
3. Ensures `log_format traffic '...'`
4. Appends `access_log /var/log/nginx/traffic.log traffic;` only when missing (no duplicates)
5. Creates the log file with proper ownership
6. Runs `nginx -t` — on failure, restores the backup
7. Reloads nginx on success

Verify only:

```bash
sudo ./install.sh --verify-only
```

Confirm traffic is being written (after a real HTTP hit):

```bash
sudo nginx -T 2>/dev/null | grep -E 'log_format traffic|traffic.log'
sudo tail -f /var/log/nginx/traffic.log
```

If the log stays empty, re-run `sudo ./install.sh` (installer now adds http-level `access_log` and patches server blocks that already define their own `access_log`).

---

## Usage

### Interactive menu

```bash
sudo ./traffic-monitor.sh
```

### Non-interactive CLI

```bash
# Full reports
./traffic-monitor.sh --report today
./traffic-monitor.sh --report 24h
./traffic-monitor.sh --today

# Demo without live nginx log
./traffic-monitor.sh --sample --report all

# ISP / ASN breakdown (Irancell / MCI / Other)
./traffic-monitor.sh --sample --isp-report --period all
./traffic-monitor.sh --isp-report --period today --out /tmp/isp.txt

# Export
./traffic-monitor.sh --export html --period today --out /tmp/report.html
./traffic-monitor.sh --export txt --period 7d

# Live monitor
./traffic-monitor.sh --live

# Plugins
./traffic-monitor.sh --plugins list
./traffic-monitor.sh --plugins enable hello_world
./traffic-monitor.sh --plugins disable live

# Doctor
./traffic-monitor.sh --doctor
```

---

## Menu description

| # | Action | Plugin |
|---|--------|--------|
| 1 | Install / Verify | `install_verify` |
| 2 | Traffic Last 24 Hours | `report_24h` |
| 3 | Today | `report_today` |
| 4 | Yesterday | `report_yesterday` |
| 5 | Last 7 Days | `report_7d` |
| 6 | Last 30 Days | `report_30d` |
| 7 | Current Log Size | `log_size` |
| 8 | Top URLs | `top_urls` |
| 9 | Top IP Addresses | `top_ips` |
| 10 | HTTP Status Codes | `status_codes` |
| 11 | ISP Traffic (ASN) | `isp_asn` |
| 12 | Export Report | `export` |
| 13 | Live Monitor | `live` |
| 14 | Reset Log | `reset` |
| 15 | Verify Installation | `verify` |
| 16 | Uninstall | `uninstall` |
| 0 | Exit | core |

Menu numbers come from plugin metadata and stay consistent as long as priorities are unchanged.

---

## ISP / ASN plugin

Plugin path: [`plugins/43-isp-asn/`](plugins/43-isp-asn/)

Traffic is classified using a **flat-file ASN/CIDR database** (not SQLite/MySQL):

| Group | Label | Seed ASN map |
|-------|-------|--------------|
| `irancell` | Irancell | AS44244 (+ related) |
| `mci` | Hamrah-e Avval (MCI) | AS197207 (+ related) |
| `other` | Other ISPs | everything else |

Files:

- `data/irancell.cidr`
- `data/mci.cidr`
- `data/other.cidr` (optional explicit ranges)
- `data/asn_map.conf`
- `asn_match.awk`

```bash
./traffic-monitor.sh --isp-report --period 7d
./traffic-monitor.sh --isp-update-db
```

**Notes**

- Accuracy depends on keeping CIDR files updated.
- CDN / reverse-proxy IPs may not represent the end-user ISP.
- Add a new ISP by dropping another `*.cidr` file and extending the matcher — no core changes.

---

## Plugin system

See the full guide: **[docs/PLUGINS.md](docs/PLUGINS.md)**

Highlights:

- Each feature is a folder with `plugin.conf` + `plugin.sh`
- Lifecycle hooks: `before_report`, `after_export`, `on_live_tick`, …
- Enable/disable without deleting code
- Example plugin: `plugins/examples/99-hello-world/` (disabled by default)

---

## Log format

```nginx
log_format traffic '$time_iso8601 $remote_addr $host $status $request_method "$request_uri" $body_bytes_sent';
access_log /var/log/nginx/traffic.log traffic;
```

---

## Configuration

Defaults live in [`config/defaults.conf`](config/defaults.conf):

- `NTM_TRAFFIC_LOG` — default `/var/log/nginx/traffic.log`
- `NTM_BACKUP_DIR` — default `/var/backups/nginx-traffic-monitor`
- `NTM_TOP_N` — default `20`
- `NTM_EXPORT_DIR` — default `/tmp/nginx-traffic-monitor`

Plugin toggles: [`config/plugins.enabled`](config/plugins.enabled)

Logrotate sample: [`share/logrotate.d/nginx-traffic-monitor`](share/logrotate.d/nginx-traffic-monitor)

```bash
sudo cp share/logrotate.d/nginx-traffic-monitor /etc/logrotate.d/
```

---

## FAQ

**Q: Can I run demos without nginx?**  
Yes. Use `--sample` to read `samples/traffic.log.sample`.

**Q: Why no database?**  
Enterprise servers often restrict extra packages. Flat files + awk keep the attack surface and ops burden minimal.

**Q: Will install break my nginx?**  
The installer always backs up first, validates with `nginx -t`, and rolls back automatically on failure.

**Q: How do I add Shatel / other ISPs?**  
Add CIDRs under `plugins/43-isp-asn/data/` and extend the awk loader / map. See [docs/PLUGINS.md](docs/PLUGINS.md).

**Q: Does live mode need root?**  
Only read access to the traffic log is required.

**Q: Is HTML export offline?**  
Yes. Pure HTML/CSS, no CDN JavaScript.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `/usr/bin/env: 'bash\r': No such file or directory` | Windows CRLF line endings. Fix: `find . -type f \( -name '*.sh' -o -name '*.awk' -o -name '*.conf' \) -exec sed -i 's/\r$//' {} +` then re-run. Prefer `git clone` on the Linux host (do not SCP a Windows working tree). |
| `nginx binary not found` | Install nginx or set `NTM_NGINX_BIN` |
| `nginx.conf not found` | Installer searches `-V`/`-t`/common paths/`find` under `/etc` `/usr/local` `/opt` `/www`. If still missing, set `NTM_NGINX_CONF=/path/to/nginx.conf` |
| `nginx -t` failed during install | Backup restored automatically; inspect the error from `nginx -t` |
| `unknown log format "traffic"` | Older installer put `access_log` before `include conf.d`. Update: `git pull && sudo ./install.sh`. Drop-in `conf.d/00-nginx-traffic-monitor.conf` must define `log_format` **then** `access_log`; main `nginx.conf` must not have an early `access_log ... traffic` before that include. |
| Empty reports / empty `traffic.log` | Logging not attached or not writable. Re-run `sudo ./install.sh` (drop-in `conf.d/00-nginx-traffic-monitor.conf` with `log_format` + `access_log`, plus per-server patches). Diagnose: `sudo wc -l /var/log/nginx/traffic.log`; `sudo nginx -T 2>/dev/null \| grep -E 'log_format traffic\|traffic.log'`; `sudo tail -f /var/log/nginx/traffic.log` while hitting the site; `sudo tail -n 50 /var/log/nginx/error.log`. |
| Permission denied on log | Run with sudo or grant read on `/var/log/nginx/traffic.log` |
| ISP all “other” | Update `*.cidr` seeds; verify client IPs are not CDN egress |
| Plugin missing from menu | `./traffic-monitor.sh --plugins list` and enable it |

Doctor command:

```bash
./traffic-monitor.sh --doctor
```

---

## Supported Linux distributions

- Ubuntu 20.04 / 22.04 / 24.04
- Debian 11 / 12
- Compatible derivatives (Linux Mint, Pop!_OS, etc.) with standard nginx packages
- **aaPanel / BT Panel** (`/www/server/nginx`) — auto-detected via running master process and panel vhost includes

Designed for POSIX-friendly Bash on systemd hosts. Other distros may work if nginx paths are set explicitly (`NTM_NGINX_BIN`, `NTM_NGINX_CONF`).

---

## Security notes

- Root is required only for nginx config changes, log rotation reset, and uninstall.
- Backups are stored under `/var/backups/nginx-traffic-monitor/`.
- Rotated logs are retained; reset never unlinks immediately.
- No network calls in the default analytics path.

---

## Roadmap

- [ ] More Iranian ISP profiles (Shatel, TIC, …) as data packs
- [ ] Anomaly / spike detection plugin
- [ ] Bot & abusive-IP heuristics plugin
- [ ] Cron-friendly mail/webhook notifier (optional soft deps)
- [ ] IPv6 CIDR matching
- [ ] Precomputed integer-range DB for very large logs

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/PLUGINS.md](docs/PLUGINS.md).

Clone for development:

```bash
git clone https://github.com/arshiyan/nginx-traffic-monitor.git
cd nginx-traffic-monitor
```

---

## License

MIT — see [LICENSE](LICENSE).

---
---

# Nginx Traffic Monitor (فارسی)

**زبان / Language:** [English](#nginx-traffic-monitor) · [فارسی](#nginx-traffic-monitor-فارسی)

تحلیل ترافیک Nginx با **Bash خالص** برای Ubuntu/Debian و aaPanel — نصب، گزارش، مانیتور زنده و خروجی HTML با معماری پلاگین و **بدون وابستگی اضافه**.

بدون Python / PHP / Node / jq / دیتابیس — فقط ابزارهای استاندارد یونیکس.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/repo-arshiyan%2Fnginx--traffic--monitor-24292e?logo=github)](https://github.com/arshiyan/nginx-traffic-monitor)

---

## نصب سریع

```bash
git clone https://github.com/arshiyan/nginx-traffic-monitor.git \
  && cd nginx-traffic-monitor \
  && sudo chmod +x install.sh traffic-monitor.sh \
  && sudo ./install.sh
```

```bash
sudo ./traffic-monitor.sh
cd nginx-traffic-monitor && git pull && sudo ./install.sh --verify-only
```

دمو بدون لاگ واقعی: `./traffic-monitor.sh --sample --report all`

---

## اسکرین‌شات‌ها

| منو | گزارش امروز | تفکیک ISP |
|:---:|:-----------:|:---------:|
| ![menu](docs/images/menu.png) | ![report](docs/images/report-today.png) | ![isp](docs/images/isp-asn.png) |

| خروجی HTML | مانیتور زنده |
|:----------:|:------------:|
| ![html](docs/images/export-html.png) | ![live](docs/images/live.png) |

---

## معرفی پروژه

`log_format traffic` را روی Nginx تنظیم می‌کند، لاگ ساخت‌یافته می‌نویسد و منوی عملیاتی + CLI (مناسب cron) ارائه می‌دهد.

قابلیت‌ها به‌صورت **پلاگین** در [`plugins/`](plugins/) هستند؛ هسته کوچک می‌ماند.

```
install.sh              → اتصال ایمن به nginx (بکاپ → ویرایش → nginx -t → reload / rollback)
traffic-monitor.sh      → منو + CLI + بارگذاری پلاگین
lib/                    → موتور هسته
plugins/                → گزارش، live، export، ISP/ASN و …
```

---

## ویژگی‌ها

| حوزه | قابلیت |
|------|--------|
| نصب | تشخیص nginx / aaPanel، بکاپ، `nginx -t`، rollback |
| گزارش | امروز / ۲۴س / ۷روز / ۳۰روز — مجموع و Topها |
| ISP/ASN | ایرانسل · همراه‌اول (MCI) · سایر (فایل CIDR) |
| زنده | RPS، پهنای باند، آخرین کلاینت/URI |
| خروجی | TXT + داشبورد HTML/CSS خالص |
| عملیات | ریست با rotate، verify، uninstall تمیز، لاگ نمونه |
| توسعه | enable/disable پلاگین، هوک، ثبت CLI |

---

## پیش‌نیازها

| مورد | کاربرد |
|------|--------|
| git | کلون از GitHub |
| bash | اجرای برنامه |
| awk, grep, sed, cut, sort, uniq | پارس و گزارش |
| find, stat, tail, wc, date | فایل‌سیستم و بازه زمانی |
| nginx | وب‌سرور هدف |
| root | فقط برای نصب / ریست / حذف |

وابستگی نرم اختیاری: `curl` (فقط راهنمای به‌روزرسانی دیتابیس ASN).

---

## نصب

### روش الف — یک خط از GitHub (پیشنهادی)

```bash
git clone https://github.com/arshiyan/nginx-traffic-monitor.git \
  && cd nginx-traffic-monitor \
  && sudo chmod +x install.sh traffic-monitor.sh \
  && sudo ./install.sh
```

### روش ب — مرحله‌به‌مرحله

```bash
git clone https://github.com/arshiyan/nginx-traffic-monitor.git
cd nginx-traffic-monitor
sudo chmod +x install.sh traffic-monitor.sh
sudo ./install.sh
```

کارهای installer:

1. پیدا کردن باینری nginx و `nginx.conf`
2. بکاپ کانفیگ در `/var/backups/nginx-traffic-monitor/`
3. اطمینان از وجود `log_format traffic`
4. افزودن `access_log` فقط اگر از قبل نباشد (بدون duplicate)
5. ساخت فایل لاگ با مالکیت مناسب
6. اجرای `nginx -t` — در صورت خطا، بازگردانی بکاپ
7. reload کردن nginx در صورت موفقیت

فقط بررسی نصب:

```bash
sudo ./install.sh --verify-only
```

اطمینان از ثبت ترافیک (بعد از یک درخواست واقعی HTTP):

```bash
sudo nginx -T 2>/dev/null | grep -E 'log_format traffic|traffic.log'
sudo tail -f /var/log/nginx/traffic.log
```

اگر لاگ خالی ماند، دوباره `sudo ./install.sh` را اجرا کنید (نصب‌کننده الان `access_log` را در سطح `http` و روی serverهایی که خودشان access_log دارند اضافه می‌کند).

---

## استفاده

### منوی تعاملی

```bash
sudo ./traffic-monitor.sh
```

### CLI غیرتعاملی

```bash
# گزارش کامل
./traffic-monitor.sh --report today
./traffic-monitor.sh --report 24h
./traffic-monitor.sh --today

# دمو بدون لاگ واقعی nginx
./traffic-monitor.sh --sample --report all

# تفکیک ISP / ASN (ایرانسل / MCI / سایر)
./traffic-monitor.sh --sample --isp-report --period all
./traffic-monitor.sh --isp-report --period today --out /tmp/isp.txt

# خروجی
./traffic-monitor.sh --export html --period today --out /tmp/report.html
./traffic-monitor.sh --export txt --period 7d

# مانیتور زنده
./traffic-monitor.sh --live

# پلاگین‌ها
./traffic-monitor.sh --plugins list
./traffic-monitor.sh --plugins enable hello_world
./traffic-monitor.sh --plugins disable live

# بررسی محیط
./traffic-monitor.sh --doctor
```

---

## توضیح منو

| # | عملیات | پلاگین |
|---|--------|--------|
| 1 | نصب / تأیید | `install_verify` |
| 2 | ترافیک ۲۴ ساعت اخیر | `report_24h` |
| 3 | امروز | `report_today` |
| 4 | دیروز | `report_yesterday` |
| 5 | ۷ روز اخیر | `report_7d` |
| 6 | ۳۰ روز اخیر | `report_30d` |
| 7 | حجم فعلی لاگ | `log_size` |
| 8 | برترین URLها | `top_urls` |
| 9 | برترین IPها | `top_ips` |
| 10 | کدهای وضعیت HTTP | `status_codes` |
| 11 | ترافیک ISP (ASN) | `isp_asn` |
| 12 | خروجی گزارش | `export` |
| 13 | مانیتور زنده | `live` |
| 14 | ریست لاگ | `reset` |
| 15 | تأیید نصب | `verify` |
| 16 | حذف نصب | `uninstall` |
| 0 | خروج | هسته |

---

## پلاگین ISP / ASN

مسیر: [`plugins/43-isp-asn/`](plugins/43-isp-asn/)

ترافیک با **دیتابیس ASN/CIDR فایلی** (نه SQLite/MySQL) دسته‌بندی می‌شود:

| گروه | برچسب | ASN اولیه |
|------|-------|-----------|
| `irancell` | ایرانسل | AS44244 (و مرتبط) |
| `mci` | همراه‌اول (MCI) | AS197207 (و مرتبط) |
| `other` | سایر ISPها | بقیه |

فایل‌ها:

- `data/irancell.cidr`
- `data/mci.cidr`
- `data/other.cidr` (اختیاری)
- `data/asn_map.conf`
- `asn_match.awk`

```bash
./traffic-monitor.sh --isp-report --period 7d
./traffic-monitor.sh --isp-update-db
```

**نکات**

- دقت وابسته به به‌روز بودن فایل‌های CIDR است.
- IPهای CDN/پروکسی ممکن است ISP واقعی کاربر نهایی نباشند.
- برای افزودن ISP جدید، فایل `*.cidr` اضافه کنید — بدون تغییر هسته.

---

## سیستم پلاگین

راهنمای کامل (انگلیسی): **[docs/PLUGINS.md](docs/PLUGINS.md)**

- هر قابلیت یک پوشه با `plugin.conf` و `plugin.sh` است
- هوک‌های چرخه حیات: `before_report`, `after_export`, `on_live_tick`, …
- فعال/غیرفعال بدون پاک کردن کد
- نمونه: `plugins/examples/99-hello-world/` (پیش‌فرض غیرفعال)

---

## فرمت لاگ

```nginx
log_format traffic '$time_iso8601 $remote_addr $host $status $request_method "$request_uri" $body_bytes_sent';
access_log /var/log/nginx/traffic.log traffic;
```

---

## تنظیمات

پیش‌فرض‌ها در [`config/defaults.conf`](config/defaults.conf):

- `NTM_TRAFFIC_LOG` — پیش‌فرض `/var/log/nginx/traffic.log`
- `NTM_BACKUP_DIR` — پیش‌فرض `/var/backups/nginx-traffic-monitor`
- `NTM_TOP_N` — پیش‌فرض `20`
- `NTM_EXPORT_DIR` — پیش‌فرض `/tmp/nginx-traffic-monitor`

فعال/غیرفعال پلاگین‌ها: [`config/plugins.enabled`](config/plugins.enabled)

نمونه logrotate: [`share/logrotate.d/nginx-traffic-monitor`](share/logrotate.d/nginx-traffic-monitor)

```bash
sudo cp share/logrotate.d/nginx-traffic-monitor /etc/logrotate.d/
```

---

## سوالات متداول (FAQ)

**آیا بدون nginx می‌توان دمو کرد؟**  
بله. با `--sample` از `samples/traffic.log.sample` استفاده کنید.

**چرا دیتابیس نیست؟**  
در سرورهای سازمانی پکیج اضافه محدود است. فایل تخت + awk سطح حمله و پیچیدگی را کم می‌کند.

**آیا نصب nginx را خراب می‌کند؟**  
اول بکاپ گرفته می‌شود، با `nginx -t` اعتبارسنجی می‌شود و در صورت خطا خودکار rollback می‌شود.

**چطور ISP دیگری مثل شاتل اضافه کنم؟**  
CIDRها را در `plugins/43-isp-asn/data/` بگذارید و matcher را گسترش دهید. جزئیات در [docs/PLUGINS.md](docs/PLUGINS.md).

**آیا live به root نیاز دارد؟**  
فقط دسترسی خواندن به لاگ ترافیک کافی است.

**آیا خروجی HTML آفلاین است؟**  
بله. فقط HTML/CSS خالص، بدون JavaScript از CDN.

---

## عیب‌یابی

| مشکل | راه حل |
|------|--------|
| `/usr/bin/env: 'bash\r': No such file or directory` | پایان‌خط CRLF ویندوزی. رفع فوری: `find . -type f \( -name '*.sh' -o -name '*.awk' -o -name '*.conf' \) -exec sed -i 's/\r$//' {} +` سپس دوباره اجرا کنید. ترجیحاً روی خود لینوکس `git clone` کنید (پوشه ویندوز را SCP نکنید). |
| `nginx binary not found` | nginx را نصب کنید یا `NTM_NGINX_BIN` را تنظیم کنید |
| `nginx.conf not found` | installer از `-V`/`-t`/مسیرهای رایج/`find` زیر `/etc` `/usr/local` `/opt` `/www` جستجو می‌کند. اگر پیدا نشد: `NTM_NGINX_CONF=/path/to/nginx.conf` |
| شکست `nginx -t` هنگام نصب | بکاپ خودکار بازگردانی شده؛ خروجی `nginx -t` را ببینید |
| `unknown log format "traffic"` | نسخهٔ قدیمی `access_log` را قبل از `include conf.d` می‌گذاشت. به‌روز کنید: `git pull && sudo ./install.sh`. در drop-in باید اول `log_format` بعد `access_log` باشد؛ در `nginx.conf` نباید `access_log ... traffic` زودرس قبل از include باشد. |
| گزارش خالی / `traffic.log` خالی | لاگ وصل نشده یا قابل نوشتن نیست. دوباره `sudo ./install.sh` (drop-in با log_format + access_log). تشخیص: `sudo wc -l /var/log/nginx/traffic.log`؛ `sudo nginx -T 2>/dev/null | grep -E 'log_format traffic|traffic.log'`؛ هنگام hit: `sudo tail -f /var/log/nginx/traffic.log`؛ `sudo tail -n 50 /var/log/nginx/error.log` |
| Permission denied روی لاگ | با sudo اجرا کنید یا دسترسی خواندن بدهید |
| همه ISPها «سایر» | فایل‌های `*.cidr` را به‌روز کنید؛ IP ممکن است CDN باشد |
| پلاگین در منو نیست | `./traffic-monitor.sh --plugins list` و enable کنید |

```bash
./traffic-monitor.sh --doctor
```

---

## توزیع‌های پشتیبانی‌شده

- Ubuntu 20.04 / 22.04 / 24.04
- Debian 11 / 12
- مشتقات سازگار با پکیج استاندارد nginx
- **aaPanel / BT Panel** (`/www/server/nginx`) — تشخیص خودکار از پروسس master و includeهای vhost پنل

در صورت نیاز: `NTM_NGINX_BIN` و `NTM_NGINX_CONF` را دستی تنظیم کنید.

---

## امنیت

- root فقط برای تغییر کانفیگ nginx، ریست لاگ و uninstall لازم است.
- بکاپ‌ها در `/var/backups/nginx-traffic-monitor/` ذخیره می‌شوند.
- لاگ‌های rotate‌شده حفظ می‌شوند؛ ریست بلافاصله فایل را حذف نمی‌کند.
- مسیر پیش‌فرض تحلیل، درخواست شبکه ندارد.

---

## نقشه راه

- [ ] پروفایل بیشتر ISPهای ایران (شاتل، مخابرات و …)
- [ ] پلاگین تشخیص جهش/anomaly
- [ ] پلاگین فیلتر بات و IP مشکوک
- [ ] اطلاع‌رسانی cron (وابستگی نرم اختیاری)
- [ ] پشتیبانی CIDR برای IPv6
- [ ] دیتابیس رنج عددی ازپیش‌محاسبه‌شده برای لاگ‌های خیلی بزرگ

---

## مشارکت

راهنما: [CONTRIBUTING.md](CONTRIBUTING.md) و [docs/PLUGINS.md](docs/PLUGINS.md)

```bash
git clone https://github.com/arshiyan/nginx-traffic-monitor.git
cd nginx-traffic-monitor
```

---

## مجوز

MIT — جزئیات در [LICENSE](LICENSE).

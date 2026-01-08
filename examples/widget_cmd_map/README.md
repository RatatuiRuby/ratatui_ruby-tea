<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Cmd.map Fractal Dashboard

Demonstrates **Fractal Architecture** using `Cmd.map` for component composition.

## Problem

Without composition, a complex app needs one giant `case` statement handling every possible message from every child—the "God Reducer" anti-pattern. This doesn't scale.

## Solution

`Cmd.map` wraps child commands so their results route through parents:

```ruby
# Child produces [:system_info, {stdout:, ...}]
child_cmd = SystemInfoWidget.fetch_cmd

# Parent wraps to produce [:stats, :system_info, {...}]
parent_cmd = Cmd.map(child_cmd) { |m| [:stats, *m] }
```

Each layer handles only its own messages. Parents pattern-match on the first element to route to the correct child.

## Architecture

```
Dashboard (root)
├── StatsPanel
│   ├── SystemInfoWidget → Cmd.exec("uname -a", :system_info)
│   └── DiskUsageWidget  → Cmd.exec("df -h", :disk_usage)
└── NetworkPanel
    ├── PingWidget       → Cmd.exec("ping -c 1 localhost", :ping)
    └── UptimeWidget     → Cmd.exec("uptime", :uptime)
```

## Hotkeys

| Key | Action |
|-----|--------|
| `s` | Fetch system info |
| `d` | Fetch disk usage |
| `p` | Ping localhost |
| `u` | Fetch uptime |
| `q` | Quit |

## Key Concepts

1. **Widget isolation**: Each widget has its own `Model`, `UPDATE`, and `fetch_cmd`. It knows nothing about parents.
2. **Message routing**: Parents prefix child messages (`:stats`, `:network`) and pattern-match to route.
3. **Recursive dispatch**: `Cmd.map` delegates inner command execution to the runtime, then transforms the result.

## Usage

```bash
ruby examples/widget_cmd_map/app.rb
```

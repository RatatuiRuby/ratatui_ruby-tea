# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "ratatui_ruby"
require "ratatui_ruby/tea"

require_relative "stats_panel"
require_relative "network_panel"

# Demonstrates Fractal Architecture with +Command.map+ for composition.
#
# == The Problem: Monolithic Update Functions
#
# As applications grow, update logic becomes unwieldy. Every child event ends up
# in one giant +case+ statement. Redux calls this the "root reducer" problem. Elm
# calls it the "God Msg" anti-pattern.
#
# == The Solution: Fractal Architecture
#
# Each child owns its own +Model+, +UPDATE+, and +VIEW+. Parents compose
# children by:
# 1. Delegating messages via +UPDATE+
# 2. Wrapping commands with +Command.map+
# 3. Calling child +VIEW+ functions to build the widget tree
#
# == Architecture
#
#   Dashboard (root)
#   ├── StatsPanel
#   │   ├── SystemInfo
#   │   └── DiskUsage
#   └── NetworkPanel
#       ├── Ping
#       └── Uptime
#
# == Running the Example
#
#   ruby examples/widget_command_map/app.rb
#
class FractalDashboard
  Command = RatatuiRuby::Tea::Command

  Model = Data.define(:stats, :network)

  INITIAL = Model.new(
    stats: StatsPanel::INITIAL,
    network: NetworkPanel::INITIAL
  )

  VIEW = lambda do |model, tui|
    hotkey = tui.style(modifiers: [:bold, :underlined])
    dim = tui.style(fg: :dark_gray)

    controls = tui.paragraph(
      text: [
        tui.text_line(spans: [
          tui.text_span(content: "s", style: hotkey),
          tui.text_span(content: ": System  "),
          tui.text_span(content: "d", style: hotkey),
          tui.text_span(content: ": Disk  "),
          tui.text_span(content: "p", style: hotkey),
          tui.text_span(content: ": Ping  "),
          tui.text_span(content: "u", style: hotkey),
          tui.text_span(content: ": Uptime  "),
          tui.text_span(content: "q", style: hotkey),
          tui.text_span(content: ": Quit"),
        ]),
      ],
      block: tui.block(title: "Fractal Dashboard (Command.map Demo)", borders: [:all], border_style: dim)
    )

    tui.layout(
      direction: :vertical,
      constraints: [tui.constraint_fill(1), tui.constraint_fill(1), tui.constraint_length(3)],
      children: [
        StatsPanel::VIEW.call(model.stats, tui),
        NetworkPanel::VIEW.call(model.network, tui),
        controls,
      ]
    )
  end

  UPDATE = lambda do |message, model|
    case message
    # Route command results to panels
    in [:stats, *rest]
      new_panel, command = StatsPanel::UPDATE.call(rest, model.stats)
      mapped_command = command ? Command.map(command) { |child_result| [:stats, *child_result] } : nil
      [model.with(stats: new_panel), mapped_command]

    in [:network, *rest]
      new_panel, command = NetworkPanel::UPDATE.call(rest, model.network)
      mapped_command = command ? Command.map(command) { |child_result| [:network, *child_result] } : nil
      [model.with(network: new_panel), mapped_command]

    # Handle user input
    in _ if message.q? || message.ctrl_c?
      Command.exit

    in _ if message.s?
      command = Command.map(SystemInfo.fetch_command) { |widget_result| [:stats, *widget_result] }
      new_stats = model.stats.with(system_info: model.stats.system_info.with(loading: true))
      [model.with(stats: new_stats), command]

    in _ if message.d?
      command = Command.map(DiskUsage.fetch_command) { |widget_result| [:stats, *widget_result] }
      new_stats = model.stats.with(disk_usage: model.stats.disk_usage.with(loading: true))
      [model.with(stats: new_stats), command]

    in _ if message.p?
      command = Command.map(Ping.fetch_command) { |widget_result| [:network, *widget_result] }
      new_network = model.network.with(ping: model.network.ping.with(loading: true))
      [model.with(network: new_network), command]

    in _ if message.u?
      command = Command.map(Uptime.fetch_command) { |widget_result| [:network, *widget_result] }
      new_network = model.network.with(uptime: model.network.uptime.with(loading: true))
      [model.with(network: new_network), command]

    else
      model
    end
  end

  def run
    RatatuiRuby::Tea.run(model: INITIAL, view: VIEW, update: UPDATE)
  end
end

FractalDashboard.new.run if __FILE__ == $PROGRAM_NAME

# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "ratatui_ruby"
require "ratatui_ruby/tea"

# Demonstrates Fractal Architecture with +Cmd.map+ for component composition.
#
# == The Problem: Monolithic Update Functions
#
# As applications grow, update logic becomes unwieldy. Every child event ends up
# in one giant +case+ statement. Redux calls this the "root reducer" problem. Elm
# calls it the "God Msg" anti-pattern. You end up with:
#
#   case msg
#   in :sidebar_loaded then ...
#   in :header_clicked then ...
#   in :footer_resized then ...
#   in :settings_saved then ...
#   # 200 more cases
#   end
#
# This does not scale. It violates single responsibility. It makes testing hard.
#
# == The Solution: Fractal Architecture
#
# Each component owns its own +Model+, +UPDATE+, and +VIEW+. Parents compose
# children by:
# 1. Delegating messages via +UPDATE+
# 2. Wrapping commands with +Cmd.map+
# 3. Calling child +VIEW+ functions to build the widget tree
#
# This pattern has many names:
# - *Elm*: The Elm Architecture (TEA) with +Cmd.map+
# - *Redux*: Combining reducers with action namespacing
# - *BubbleTea* (Go): The +tea.Model+ interface with +tea.Cmd+ forwarding
# - *Rust Ratatui*: Not built-in, but common in community examples
#
# == Cross-Framework Analogies
#
# [For Rails developers]
#   Think of each widget as a "concern" or "service object" with its own state.
#   The +UPDATE+ lambda is like a controller action that returns the next state
#   instead of rendering a view. Commands are like background jobs (Sidekiq).
#   The +VIEW+ lambda is like a view partial—reusable rendering logic.
#
# [For Angular developers]
#   Each module is like a component. +Model+ is the component state. +UPDATE+
#   handles events. +VIEW+ is the template. +Cmd.map+ is like piping child
#   outputs through parent handlers. No two-way binding—data flows one way.
#
# [For Vue/Vuex developers]
#   +Model+ is the Vuex store. +UPDATE+ is a mutation handler. +VIEW+ is the
#   template. +Cmd+ is an action for side effects. +Cmd.map+ is namespacing.
#
# [For React/Redux developers]
#   +Model+ is state. +UPDATE+ is a reducer. +VIEW+ is a functional component.
#   Messages are actions. +Cmd+ is redux-saga/thunk. +Cmd.map+ is action prefixing.
#
# [For Rust Ratatui developers]
#   This is TEA from BubbleTea. +Model+ is your app struct. +UPDATE+ is the
#   +update+ method. +VIEW+ is the +view+ method returning widget trees.
#
# [For Go BubbleTea developers]
#   Nearly identical. +Model+ = +tea.Model+. +UPDATE+ = +Update+ method.
#   +VIEW+ = +View+ method. +Cmd.map+ wraps child +tea.Cmd+ returns.
#
# == Architecture
#
#   Dashboard (root)
#   ├── StatsPanel
#   │   ├── SystemInfoWidget → Model, UPDATE, VIEW, fetch_cmd
#   │   └── DiskUsageWidget  → Model, UPDATE, VIEW, fetch_cmd
#   └── NetworkPanel
#       ├── PingWidget       → Model, UPDATE, VIEW, fetch_cmd
#       └── UptimeWidget     → Model, UPDATE, VIEW, fetch_cmd
#
# == How Message Routing Works
#
# 1. User presses 's' (system info)
# 2. Dashboard UPDATE returns:
#    +Cmd.map(widget_cmd) { |widget_result| [:stats, *widget_result] }+
# 3. Runtime executes +inner_cmd+ (the shell command)
# 4. Shell returns +[:system_info, {stdout: "Darwin..."}]+
# 5. Mapper transforms to +[:stats, :system_info, {stdout: "Darwin..."}]+
# 6. Dashboard UPDATE receives message, pattern-matches on +:stats+, delegates
# 7. StatsPanel UPDATE receives +[:system_info, {...}]+, updates its model
# 8. New model bubbles up, Dashboard VIEW calls child VIEWs to re-render
#
# == Running the Example
#
#   ruby examples/widget_cmd_map/app.rb
#
class WidgetCmdMap
  Cmd = RatatuiRuby::Tea::Cmd

  # ============================================================================
  # CHILD WIDGETS
  # ============================================================================
  #
  # Each widget is a self-contained module with:
  # - +Model+: The state (a frozen Data struct for immutability)
  # - +INITIAL+: The starting state
  # - +UPDATE+: A lambda that handles messages → returns +[new_model, cmd]+
  # - +VIEW+: A lambda that renders the widget → returns a widget tree
  # - +fetch_cmd+: A factory method returning the command to execute
  #
  # Widgets know nothing about their parents. Parents call their VIEW.

  # Fetches and displays system information via +uname -a+.
  module SystemInfoWidget
    Model = Data.define(:output, :loading)
    INITIAL = Model.new(output: "Press 's' for system info", loading: false)

    # Renders this widget. Parents call this with the widget's model.
    #
    # [For React developers]
    #   This is a functional component. It receives props (model, tui) and
    #   returns a React element (widget). No hooks, no lifecycle—pure function.
    #
    # [For Angular developers]
    #   This is like a component template extracted into a pure function.
    #   The +tui+ parameter provides widget constructors (like a template DSL).
    VIEW = lambda do |model, tui|
      tui.paragraph(
        text: model.output,
        block: tui.block(title: "System Info", borders: [:all], border_style: { fg: :cyan })
      )
    end

    UPDATE = lambda do |msg, model|
      case msg
      in [:system_info, { stdout:, status: 0 }]
        [model.with(output: Ractor.make_shareable(stdout.strip), loading: false), nil]
      in [:system_info, { stderr:, _status: }]
        [model.with(output: Ractor.make_shareable("Error: #{stderr.strip}"), loading: false), nil]
      else
        [model, nil]
      end
    end

    def self.fetch_cmd
      Cmd.exec("uname -a", :system_info)
    end
  end

  # Fetches and displays disk usage via +df -h+.
  module DiskUsageWidget
    Model = Data.define(:output, :loading)
    INITIAL = Model.new(output: "Press 'd' for disk usage", loading: false)

    VIEW = lambda do |model, tui|
      tui.paragraph(
        text: model.output,
        block: tui.block(title: "Disk Usage", borders: [:all], border_style: { fg: :cyan })
      )
    end

    UPDATE = lambda do |msg, model|
      case msg
      in [:disk_usage, { stdout:, status: 0 }]
        lines = Ractor.make_shareable(stdout.lines.first(4).join.strip)
        [model.with(output: lines, loading: false), nil]
      in [:disk_usage, { stderr:, _status: }]
        [model.with(output: Ractor.make_shareable("Error: #{stderr.strip}"), loading: false), nil]
      else
        [model, nil]
      end
    end

    def self.fetch_cmd
      Cmd.exec("df -h", :disk_usage)
    end
  end

  # Pings localhost to check network connectivity.
  module PingWidget
    Model = Data.define(:output, :loading)
    INITIAL = Model.new(output: "Press 'p' for ping", loading: false)

    VIEW = lambda do |model, tui|
      tui.paragraph(
        text: model.output,
        block: tui.block(title: "Ping", borders: [:all], border_style: { fg: :green })
      )
    end

    UPDATE = lambda do |msg, model|
      case msg
      in [:ping, { stdout:, status: 0 }]
        [model.with(output: Ractor.make_shareable(stdout.strip), loading: false), nil]
      in [:ping, { stderr:, _status: }]
        [model.with(output: Ractor.make_shareable("Error: #{stderr.strip}"), loading: false), nil]
      else
        [model, nil]
      end
    end

    def self.fetch_cmd
      Cmd.exec("ping -c 1 localhost", :ping)
    end
  end

  # Displays system uptime.
  module UptimeWidget
    Model = Data.define(:output, :loading)
    INITIAL = Model.new(output: "Press 'u' for uptime", loading: false)

    VIEW = lambda do |model, tui|
      tui.paragraph(
        text: model.output,
        block: tui.block(title: "Uptime", borders: [:all], border_style: { fg: :green })
      )
    end

    UPDATE = lambda do |msg, model|
      case msg
      in [:uptime, { stdout:, status: 0 }]
        [model.with(output: Ractor.make_shareable(stdout.strip), loading: false), nil]
      in [:uptime, { stderr:, _status: }]
        [model.with(output: Ractor.make_shareable("Error: #{stderr.strip}"), loading: false), nil]
      else
        [model, nil]
      end
    end

    def self.fetch_cmd
      Cmd.exec("uptime", :uptime)
    end
  end

  # ============================================================================
  # PARENT PANELS
  # ============================================================================
  #
  # Panels compose widgets. Each panel has:
  # - +Model+: Contains child widget models
  # - +UPDATE+: Routes messages to child UPDATE functions
  # - +VIEW+: Calls child VIEW functions and arranges them in a layout
  #
  # [For Rails developers]
  #   Panels are like "controllers" that coordinate "service objects" (widgets).
  #   The VIEW is like a layout that renders partials (child VIEWs).

  # Composes SystemInfoWidget and DiskUsageWidget in a horizontal layout.
  module StatsPanel
    Model = Data.define(:system_info, :disk_usage)

    INITIAL = Model.new(
      system_info: SystemInfoWidget::INITIAL,
      disk_usage: DiskUsageWidget::INITIAL
    )

    # Renders this panel by calling child VIEWs and arranging them.
    #
    # [For React developers]
    #   This is component composition. The panel component renders child
    #   components and arranges them in a layout. Each child is a pure function.
    VIEW = lambda do |model, tui|
      tui.layout(
        direction: :horizontal,
        constraints: [tui.constraint_percentage(50), tui.constraint_percentage(50)],
        children: [
          SystemInfoWidget::VIEW.call(model.system_info, tui),
          DiskUsageWidget::VIEW.call(model.disk_usage, tui),
        ]
      )
    end

    UPDATE = lambda do |msg, model|
      case msg
      in [:system_info, *rest]
        child_msg = [:system_info, *rest]
        new_child, cmd = SystemInfoWidget::UPDATE.call(child_msg, model.system_info)
        [model.with(system_info: new_child), cmd]
      in [:disk_usage, *rest]
        child_msg = [:disk_usage, *rest]
        new_child, cmd = DiskUsageWidget::UPDATE.call(child_msg, model.disk_usage)
        [model.with(disk_usage: new_child), cmd]
      else
        [model, nil]
      end
    end
  end

  # Composes PingWidget and UptimeWidget in a horizontal layout.
  module NetworkPanel
    Model = Data.define(:ping, :uptime)

    INITIAL = Model.new(
      ping: PingWidget::INITIAL,
      uptime: UptimeWidget::INITIAL
    )

    VIEW = lambda do |model, tui|
      tui.layout(
        direction: :horizontal,
        constraints: [tui.constraint_percentage(50), tui.constraint_percentage(50)],
        children: [
          PingWidget::VIEW.call(model.ping, tui),
          UptimeWidget::VIEW.call(model.uptime, tui),
        ]
      )
    end

    UPDATE = lambda do |msg, model|
      case msg
      in [:ping, *rest]
        child_msg = [:ping, *rest]
        new_child, cmd = PingWidget::UPDATE.call(child_msg, model.ping)
        [model.with(ping: new_child), cmd]
      in [:uptime, *rest]
        child_msg = [:uptime, *rest]
        new_child, cmd = UptimeWidget::UPDATE.call(child_msg, model.uptime)
        [model.with(uptime: new_child), cmd]
      else
        [model, nil]
      end
    end
  end

  # ============================================================================
  # ROOT DASHBOARD
  # ============================================================================
  #
  # The root composes panels. It:
  # 1. Handles user input (key presses)
  # 2. Triggers commands wrapped with +Cmd.map+
  # 3. Routes command results to panels via +UPDATE+
  # 4. Calls panel +VIEW+ functions to build the complete widget tree

  Model = Data.define(:stats, :network)

  INITIAL = Model.new(
    stats: StatsPanel::INITIAL,
    network: NetworkPanel::INITIAL
  )

  # Renders the entire UI by calling child panel VIEWs.
  #
  # [For all audiences]
  #   Notice how VIEW composes child VIEWs. Each component renders itself.
  #   The root just arranges panels and adds the controls bar. This is
  #   the same composition pattern used in React, Vue, Angular, and Elm.
  VIEW = lambda do |model, tui|
    hotkey = tui.style(modifiers: [:bold, :underlined])
    dim = tui.style(fg: :dark_gray)

    # Controls bar at the bottom
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
      block: tui.block(title: "Fractal Dashboard (Cmd.map Demo)", borders: [:all], border_style: dim)
    )

    # Layout: call child VIEWs and arrange in vertical stack
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

  # Handles all events. Returns +[new_model, cmd]+ or just +cmd+.
  #
  # == The Key Insight: +Cmd.map+
  #
  # When triggering a child command, wrap it to prefix the result:
  #
  #   child_cmd = SystemInfoWidget.fetch_cmd
  #   # Produces: [:system_info, {stdout: "Darwin..."}]
  #
  #   parent_cmd = Cmd.map(child_cmd) { |child_result| [:stats, *child_result] }
  #   # Produces: [:stats, :system_info, {stdout: "Darwin..."}]
  #
  # The root UPDATE then routes based on the first element.
  UPDATE = lambda do |msg, model|
    case msg
    # Route command results to panels
    in [:stats, *rest]
      new_panel, cmd = StatsPanel::UPDATE.call(rest, model.stats)
      mapped_cmd = cmd ? Cmd.map(cmd) { |child_result| [:stats, *child_result] } : nil
      [model.with(stats: new_panel), mapped_cmd]

    in [:network, *rest]
      new_panel, cmd = NetworkPanel::UPDATE.call(rest, model.network)
      mapped_cmd = cmd ? Cmd.map(cmd) { |child_result| [:network, *child_result] } : nil
      [model.with(network: new_panel), mapped_cmd]

    # Handle user input
    in _ if msg.q? || msg.ctrl_c?
      Cmd.quit

    in _ if msg.s?
      cmd = Cmd.map(SystemInfoWidget.fetch_cmd) { |widget_result| [:stats, *widget_result] }
      new_stats = model.stats.with(system_info: model.stats.system_info.with(loading: true))
      [model.with(stats: new_stats), cmd]

    in _ if msg.d?
      cmd = Cmd.map(DiskUsageWidget.fetch_cmd) { |widget_result| [:stats, *widget_result] }
      new_stats = model.stats.with(disk_usage: model.stats.disk_usage.with(loading: true))
      [model.with(stats: new_stats), cmd]

    in _ if msg.p?
      cmd = Cmd.map(PingWidget.fetch_cmd) { |widget_result| [:network, *widget_result] }
      new_network = model.network.with(ping: model.network.ping.with(loading: true))
      [model.with(network: new_network), cmd]

    in _ if msg.u?
      cmd = Cmd.map(UptimeWidget.fetch_cmd) { |widget_result| [:network, *widget_result] }
      new_network = model.network.with(uptime: model.network.uptime.with(loading: true))
      [model.with(network: new_network), cmd]

    else
      model
    end
  end

  def run
    RatatuiRuby::Tea.run(model: INITIAL, view: VIEW, update: UPDATE)
  end
end

WidgetCmdMap.new.run if __FILE__ == $PROGRAM_NAME

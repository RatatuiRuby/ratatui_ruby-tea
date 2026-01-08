# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "../bags/stats_panel"
require_relative "../bags/network_panel"

# Shared Model, INITIAL, and VIEW for the Dashboard.
#
# This module is extended by the three UPDATE variants to demonstrate
# the progression from verbose manual routing to declarative DSL.
module DashboardBase
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
      block: tui.block(title: "Fractal Dashboard", borders: [:all], border_style: dim)
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
end

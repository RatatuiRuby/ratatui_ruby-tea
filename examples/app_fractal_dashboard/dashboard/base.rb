# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "../bags/stats_panel"
require_relative "../bags/network_panel"
require_relative "../bags/custom_shell_modal"

# Shared Model, INITIAL, and VIEW for the Dashboard.
#
# This module is extended by the three UPDATE variants to demonstrate
# the progression from verbose manual routing to declarative DSL.
module DashboardBase
  Command = RatatuiRuby::Tea::Command

  Model = Data.define(:stats, :network, :shell_modal)

  INITIAL = Model.new(
    stats: StatsPanel::INITIAL,
    network: NetworkPanel::INITIAL,
    shell_modal: CustomShellModal::INITIAL
  )

  VIEW = lambda do |model, tui|
    modal_active = CustomShellModal.active?(model.shell_modal)
    hotkey, label_style = if modal_active
      [tui.style(fg: :dark_gray), tui.style(fg: :dark_gray)]
    else
      [tui.style(modifiers: [:bold, :underlined]), nil]
    end
    dim = tui.style(fg: :dark_gray)

    controls = tui.paragraph(
      text: [
        tui.text_line(spans: [
          tui.text_span(content: "s", style: hotkey),
          tui.text_span(content: ": System  ", style: label_style),
          tui.text_span(content: "d", style: hotkey),
          tui.text_span(content: ": Disk  ", style: label_style),
          tui.text_span(content: "p", style: hotkey),
          tui.text_span(content: ": Ping  ", style: label_style),
          tui.text_span(content: "u", style: hotkey),
          tui.text_span(content: ": Uptime  ", style: label_style),
          tui.text_span(content: "c", style: hotkey),
          tui.text_span(content: ": Custom  ", style: label_style),
          tui.text_span(content: "q", style: hotkey),
          tui.text_span(content: ": Quit", style: label_style),
        ]),
      ],
      block: tui.block(title: "Fractal Dashboard", borders: [:all], border_style: dim)
    )

    dashboard = tui.layout(
      direction: :vertical,
      constraints: [tui.constraint_fill(1), tui.constraint_fill(1), tui.constraint_length(3)],
      children: [
        StatsPanel::VIEW.call(model.stats, tui, disabled: modal_active),
        NetworkPanel::VIEW.call(model.network, tui, disabled: modal_active),
        controls,
      ]
    )

    # Compose modal overlay if active
    modal_widget = CustomShellModal::VIEW.call(model.shell_modal, tui)
    if modal_widget
      tui.overlay(layers: [dashboard, modal_widget])
    else
      dashboard
    end
  end
end

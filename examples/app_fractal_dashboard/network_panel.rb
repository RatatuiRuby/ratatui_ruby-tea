# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "ping"
require_relative "uptime"

# Composes Ping and Uptime in a horizontal layout.
module NetworkPanel
  Model = Data.define(:ping, :uptime)

  INITIAL = Model.new(
    ping: Ping::INITIAL,
    uptime: Uptime::INITIAL
  )

  VIEW = lambda do |model, tui|
    tui.layout(
      direction: :horizontal,
      constraints: [tui.constraint_percentage(50), tui.constraint_percentage(50)],
      children: [
        Ping::VIEW.call(model.ping, tui),
        Uptime::VIEW.call(model.uptime, tui),
      ]
    )
  end

  UPDATE = lambda do |message, model|
    case message
    in [:ping, *rest]
      child_message = [:ping, *rest]
      new_child, command = Ping::UPDATE.call(child_message, model.ping)
      [model.with(ping: new_child), command]
    in [:uptime, *rest]
      child_message = [:uptime, *rest]
      new_child, command = Uptime::UPDATE.call(child_message, model.uptime)
      [model.with(uptime: new_child), command]
    else
      [model, nil]
    end
  end
end

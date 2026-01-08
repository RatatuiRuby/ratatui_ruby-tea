# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# Pings localhost to check network connectivity.
# A bag for pinging localhost.
module Ping
  Command = RatatuiRuby::Tea::Command

  Model = Data.define(:output, :loading)
  INITIAL = Model.new(output: "Press 'p' for ping", loading: false)

  VIEW = lambda do |model, tui|
    tui.paragraph(
      text: model.output,
      block: tui.block(title: "Ping", borders: [:all], border_style: { fg: :green })
    )
  end

  UPDATE = lambda do |message, model|
    case message
    in [:ping, { stdout:, status: 0 }]
      [model.with(output: Ractor.make_shareable(stdout.strip), loading: false), nil]
    in [:ping, { stderr:, _status: }]
      [model.with(output: Ractor.make_shareable("Error: #{stderr.strip}"), loading: false), nil]
    else
      [model, nil]
    end
  end

  def self.fetch_command
    Command.system("ping -c 1 localhost", :ping)
  end
end

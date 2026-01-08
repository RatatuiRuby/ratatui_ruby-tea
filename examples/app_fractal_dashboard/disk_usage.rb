# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# Fetches and displays disk usage via +df -h+.
# A bag for fetching and displaying disk usage.
module DiskUsage
  Command = RatatuiRuby::Tea::Command

  Model = Data.define(:output, :loading)
  INITIAL = Model.new(output: "Press 'd' for disk usage", loading: false)

  VIEW = lambda do |model, tui|
    tui.paragraph(
      text: model.output,
      block: tui.block(title: "Disk Usage", borders: [:all], border_style: { fg: :cyan })
    )
  end

  UPDATE = lambda do |message, model|
    case message
    in [:disk_usage, { stdout:, status: 0 }]
      lines = Ractor.make_shareable(stdout.lines.first(4).join.strip)
      [model.with(output: lines, loading: false), nil]
    in [:disk_usage, { stderr:, _status: }]
      [model.with(output: Ractor.make_shareable("Error: #{stderr.strip}"), loading: false), nil]
    else
      [model, nil]
    end
  end

  def self.fetch_command
    Command.system("df -h", :disk_usage)
  end
end

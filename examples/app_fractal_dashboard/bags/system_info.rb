# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# Fetches and displays system information via +uname -a+.
# A bag for fetching and displaying system information.
module SystemInfo
  Command = RatatuiRuby::Tea::Command

  Model = Data.define(:output, :loading)
  INITIAL = Model.new(output: "Press 's' for system info", loading: false)

  VIEW = lambda do |model, tui, disabled: false|
    text_style = if disabled && model.output == INITIAL.output
      tui.style(fg: :dark_gray)
    else
      nil
    end

    tui.paragraph(
      text: tui.text_span(content: model.output, style: text_style),
      block: tui.block(title: "System Info", borders: [:all], border_style: { fg: :cyan })
    )
  end

  UPDATE = lambda do |message, model|
    case message
    in [:system_info, { stdout:, status: 0 }]
      [model.with(output: Ractor.make_shareable(stdout.strip), loading: false), nil]
    in [:system_info, { stderr:, _status: }]
      [model.with(output: Ractor.make_shareable("Error: #{stderr.strip}"), loading: false), nil]
    else
      [model, nil]
    end
  end

  def self.fetch_command
    Command.system("uname -a", :system_info)
  end
end

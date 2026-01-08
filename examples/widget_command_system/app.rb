# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "ratatui_ruby"
require "ratatui_ruby/tea"

# Demonstrates the Command.execute command for running shell commands.
#
# This example shows how to execute shell commands and handle both success
# and failure cases using pattern matching in update. The split layout shows
# command output in the main area with controls at the bottom.
#
# === Examples
#
# Run the demo from the terminal:
#
#   ruby examples/widget_cmd_exec/app.rb
#
# rdoc-image:/doc/images/widget_cmd_exec.png
class WidgetCommandSystem
  Model = Data.define(:result, :loading, :last_command)
  INITIAL = Model.new(
    result: "Press a key to run a command...",
    loading: false,
    last_command: nil
  )

  VIEW = -> (model, tui) do
    hotkey_style = tui.style(modifiers: [:bold, :underlined])
    dim_style = tui.style(fg: :dark_gray)

    # Styles
    border_color = if model.loading
      "yellow"
    elsif model.result.start_with?("Error")
      "red"
    else
      "cyan"
    end

    title = model.last_command ? "Output: #{model.last_command}" : "Command.execute Demo"
    content_text = model.loading ? "Running command..." : model.result

    # 1. Main Output Widget
    output_widget = tui.paragraph(
      text: content_text,
      block: tui.block(
        title:,
        borders: [:all],
        border_style: { fg: border_color },
        padding: 1
      )
    )

    # 2. Control Panel Widget
    control_widget = tui.paragraph(
      text: [
        tui.text_line(spans: [
          tui.text_span(content: "d", style: hotkey_style),
          tui.text_span(content: ": Directory listing (ls -la)  "),
          tui.text_span(content: "u", style: hotkey_style),
          tui.text_span(content: ": System info (uname -a)"),
        ]),
        tui.text_line(spans: [
          tui.text_span(content: "f", style: hotkey_style),
          tui.text_span(content: ": Force failure  "),
          tui.text_span(content: "s", style: hotkey_style),
          tui.text_span(content: ": Sleep (3s)  "),
          tui.text_span(content: "q", style: hotkey_style),
          tui.text_span(content: ": Quit"),
        ]),
      ],
      block: tui.block(
        title: "Controls",
        borders: [:all],
        border_style: dim_style
      )
    )

    # Return the Root Layout Widget (Blueprint)
    tui.layout(
      direction: :vertical,
      constraints: [
        tui.constraint_fill(1),
        tui.constraint_length(6),
      ],
      children: [
        output_widget,
        control_widget,
      ]
    )
  end

  UPDATE = -> (message, model) do
    case message
    # Handle command results
    in [:got_output, { stdout:, status: 0 }]
      [model.with(result: stdout.strip.freeze, loading: false), nil]
    in [:got_output, { stderr:, status: }]
      [model.with(result: "Error (exit #{status}): #{stderr.strip}".freeze, loading: false), nil]

    # Handle key presses
    in _ if message.q? || message.ctrl_c?
      RatatuiRuby::Tea::Command.exit
    in _ if message.d?
      [model.with(loading: true, last_command: "ls -la"), RatatuiRuby::Tea::Command.system("ls -la", :got_output)]
    in _ if message.u?
      [model.with(loading: true, last_command: "uname -a"), RatatuiRuby::Tea::Command.system("uname -a", :got_output)]
    in _ if message.s?
      command = "sleep 3 && echo 'Slept for 3s'"
      [model.with(loading: true, last_command: cmd.freeze), RatatuiRuby::Tea::Command.system(cmd, :got_output)]
    in _ if message.f?
      # Intentional failure to demonstrate error handling
      command = "ls /nonexistent_path_12345"
      [model.with(loading: true, last_command: cmd.freeze), RatatuiRuby::Tea::Command.system(cmd, :got_output)]
    else
      model
    end
  end

  def run
    RatatuiRuby::Tea.run(model: INITIAL, view: VIEW, update: UPDATE)
  end
end

WidgetCommandSystem.new.run if __FILE__ == $PROGRAM_NAME

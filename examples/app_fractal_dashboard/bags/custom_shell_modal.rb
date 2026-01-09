# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require_relative "custom_shell_input"
require_relative "custom_shell_output"

# Parent coordinator bag for custom shell modal.
#
# Routes to active child (input or output). Checks child model state for transitions.
module CustomShellModal
  Command = RatatuiRuby::Tea::Command

  Model = Data.define(:mode, :input, :output)
  INITIAL = Ractor.make_shareable(Model.new(mode: :none, input: CustomShellInput::INITIAL, output: CustomShellOutput::INITIAL))

  VIEW = lambda do |model, tui|
    case model.mode
    when :none then nil
    when :input then CustomShellInput::VIEW.call(model.input, tui)
    when :output then CustomShellOutput::VIEW.call(model.output, tui)
    end
  end

  UPDATE = lambda do |message, model|
    case model.mode
    when :input
      new_input, cmd = CustomShellInput::UPDATE.call(message, model.input)

      if new_input.cancelled
        [INITIAL, nil]
      elsif new_input.submitted
        shell_cmd = new_input.text
        new_output = CustomShellOutput::INITIAL.with(command: shell_cmd, running: true)
        [
          model.with(mode: :output, input: CustomShellInput::INITIAL, output: new_output),
          Command.system(shell_cmd, :shell_output, stream: true),
]
      else
        [model.with(input: new_input), cmd]
      end

    when :output
      # Route streaming messages (strip :shell_output prefix)
      routed = case message
               in [:shell_output, *rest] then rest
               else message
      end

      new_output, cmd = CustomShellOutput::UPDATE.call(routed, model.output)

      if new_output.dismissed
        [INITIAL, nil]
      else
        [model.with(output: new_output), cmd]
      end

    else
      [model, nil]
    end
  end

  def self.open
    INITIAL.with(mode: :input, input: CustomShellInput::INITIAL)
  end

  def self.active?(model)
    model.mode != :none
  end
end

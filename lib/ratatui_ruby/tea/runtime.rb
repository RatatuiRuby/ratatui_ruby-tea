# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "ratatui_ruby"

module RatatuiRuby
  module Tea
    # Runs the Model-View-Update event loop.
    #
    # Applications need a render loop. You poll events, update state, redraw. Every frame.
    # The boilerplate is tedious and error-prone.
    #
    # This class handles the loop. You provide the model, view, and update. It handles the rest.
    #
    # Use it to build applications with predictable state.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-FileCopyrightText: 2026 Kerrick Long
    # SPDX-License-Identifier: MIT-0
    #++
    #   RatatuiRuby::Tea.run(
    #     model: { count: 0 }.freeze,
    #     view: ->(m, tui) { tui.paragraph(text: m[:count].to_s) },
    #     update: ->(msg, m) { msg.q? ? [m, Cmd.quit] : [m, nil] }
    #   )
    #--
    # SPDX-SnippetEnd
    #++
    class Runtime
      # Starts the MVU event loop.
      #
      # Runs until the update function returns a <tt>Cmd.quit</tt> command.
      #
      # [model] Initial application state (immutable).
      # [view] Callable receiving <tt>(model, tui)</tt>, returns a widget.
      # [update] Callable receiving <tt>(msg, model)</tt>, returns <tt>[new_model, cmd]</tt> or just <tt>new_model</tt>.
      # [init] Optional callable to run at startup. Returns a message for update.
      def self.run(model:, view:, update:, init: nil)
        validate_ractor_shareable!(model, "model")

        # Execute init command synchronously if provided
        if init
          init_msg = init.call
          result = update.call(init_msg, model)
          model, _cmd = normalize_update_result(result, model)
          validate_ractor_shareable!(model, "model")
        end

        RatatuiRuby.run do |tui|
          loop do
            tui.draw do |frame|
              widget = view.call(model, tui)
              validate_view_result!(widget)
              frame.render_widget(widget, frame.area)
            end
            msg = tui.poll_event
            result = update.call(msg, model)
            model, cmd = normalize_update_result(result, model)
            validate_ractor_shareable!(model, "model")
            break if cmd.is_a?(Cmd::Quit)

            # Execute Cmd::Exec synchronously (blocking)
            if cmd.is_a?(Cmd::Exec)
              exec_msg = execute_cmd_exec(cmd)
              result = update.call(exec_msg, model)
              model, cmd = normalize_update_result(result, model)
              validate_ractor_shareable!(model, "model")
              break if cmd.is_a?(Cmd::Quit)
            end
          end
        end
      end

      # Validates the view returned a widget.
      #
      # Views return widget trees. Returning +nil+ is a bug—you forgot to
      # return something. For an intentionally empty screen, use TUI#clear.
      private_class_method def self.validate_view_result!(widget)
        return unless widget.nil?

        raise RatatuiRuby::Error::Invariant,
          "View returned nil. Return a widget, or use TUI#clear for an empty screen."
      end

      # Detects whether +result+ is a +[model, cmd]+ tuple, a plain model, or a Cmd alone.
      #
      # Returns +[model, cmd]+ in all cases.
      private_class_method def self.normalize_update_result(result, previous_model)
        return result if result.is_a?(Array) && result.size == 2 && valid_cmd?(result[1])
        return [previous_model, result] if valid_cmd?(result)

        [result, nil]
      end

      # Returns +true+ if +value+ is a valid command (+nil+ or a +Cmd+ type).
      private_class_method def self.valid_cmd?(value)
        value.nil? || value.class.name&.start_with?("RatatuiRuby::Tea::Cmd::")
      end

      # Validates an object is Ractor-shareable (deeply frozen).
      #
      # Models and messages must be shareable for future Ractor support.
      # Mutable objects cause race conditions. Freeze your data.
      private_class_method def self.validate_ractor_shareable!(object, name)
        return if Ractor.shareable?(object)

        raise RatatuiRuby::Error::Invariant,
          "#{name.capitalize} is not Ractor-shareable. Call .freeze on your #{name}."
      end

      # Executes a shell command and produces the result message.
      #
      # Returns <tt>[tag, {stdout:, stderr:, status:}]</tt> for update.
      # Message is made Ractor-shareable (deeply frozen).
      # Runs synchronously. For async execution, use the worker pool (future).
      private_class_method def self.execute_cmd_exec(cmd)
        require "open3"
        stdout, stderr, status = Open3.capture3(cmd.command)
        Ractor.make_shareable([cmd.tag, { stdout:, stderr:, status: status.exitstatus }])
      end
    end
  end
end

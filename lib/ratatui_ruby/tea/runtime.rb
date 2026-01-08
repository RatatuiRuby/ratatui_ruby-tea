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

        queue = Queue.new

        catch(:quit) do
          RatatuiRuby.run do |tui|
            loop do
              tui.draw do |frame|
                widget = view.call(model, tui)
                validate_view_result!(widget)
                frame.render_widget(widget, frame.area)
              end

              # 1. Handle user input (blocks up to 16ms)
              msg = tui.poll_event

              # If provided, handle the event
              unless msg.is_a?(RatatuiRuby::Event::None)
                result = update.call(msg, model)
                model, cmd = normalize_update_result(result, model)
                validate_ractor_shareable!(model, "model")
                throw :quit if cmd.is_a?(Cmd::Quit)

                dispatch(cmd, queue) if cmd
              end

              # 2. Check for background outcomes
              until queue.empty?
                begin
                  bg_msg = queue.pop(true)
                  result = update.call(bg_msg, model)
                  model, cmd = normalize_update_result(result, model)
                  validate_ractor_shareable!(model, "model")
                  throw :quit if cmd.is_a?(Cmd::Quit)

                  dispatch(cmd, queue) if cmd
                rescue ThreadError
                  break
                end
              end
            end
          end
        end

        model
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
          "#{name.capitalize} is not Ractor-shareable. Use Ractor.make_shareable or Object#freeze."
      end

      # Dispatches a command to the worker pool.
      #
      # Spawns a thread for async commands. Pushes result to +queue+.
      # Handles nested commands (Batch, Sequence) recursively.
      private_class_method def self.dispatch(cmd, queue)
        case cmd
        when Cmd::Exec
          Thread.new do
            require "open3"
            stdout, stderr, status = Open3.capture3(cmd.command)
            msg = [cmd.tag, { stdout:, stderr:, status: status.exitstatus }]
            queue << Ractor.make_shareable(msg)
          rescue => e
            # Should we send an error message? For now, crash in debug, ignore in prod?
            # Better to rely on Open3 not raising for standard execution.
          end
          # TODO: Add Batch, Sequence, NetHttp
        end
      end
    end
  end
end

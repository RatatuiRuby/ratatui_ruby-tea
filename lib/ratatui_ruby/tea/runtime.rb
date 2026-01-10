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
    #     view: ->(model, tui) { tui.paragraph(text: model[:count].to_s) },
    #     update: ->(message, model) { message.q? ? [model, Command.exit] : [model, nil] }
    #   )
    #--
    # SPDX-SnippetEnd
    #++
    class Runtime
      # Starts the MVU event loop.
      #
      # Runs until the update function returns a <tt>Command.exit</tt> command.
      #
      # [model] Initial application state (immutable).
      # [view] Callable receiving <tt>(model, tui)</tt>, returns a widget.
      # [update] Callable receiving <tt>(message, model)</tt>, returns <tt>[new_model, command]</tt> or just <tt>new_model</tt>.
      # [init] Optional callable to run at startup. Returns a message for update.
      def self.run(model:, view:, update:, init: nil)
        validate_ractor_shareable!(model, "model")

        # Execute init command synchronously if provided
        if init
          init_message = init.call
          result = update.call(init_message, model)
          model, _command = normalize_update_result(result, model)
          validate_ractor_shareable!(model, "model")
        end

        queue = Queue.new
        pending_threads = []

        catch(:quit) do
          RatatuiRuby.run do |tui|
            loop do
              tui.draw do |frame|
                widget = view.call(model, tui)
                validate_view_result!(widget)
                frame.render_widget(widget, frame.area)
              end

              # 1. Handle user input (blocks up to 16ms)
              message = tui.poll_event

              # If provided, handle the event
              unless message.is_a?(RatatuiRuby::Event::None)
                result = update.call(message, model)
                model, command = normalize_update_result(result, model)
                validate_ractor_shareable!(model, "model")
                throw :quit if command.is_a?(Command::Exit)

                thread = dispatch(command, queue) if command
                pending_threads << thread if thread
              end

              # 2. Check for synthetic events (Sync)
              # This comes AFTER poll_event so Sync waits for commands dispatched
              # by the preceding event (e.g., inject_key("a"); inject_sync)
              if RatatuiRuby::SyntheticEvents.pending?
                synthetic = RatatuiRuby::SyntheticEvents.pop
                if synthetic&.sync?
                  # Wait for all pending threads to complete
                  pending_threads.each(&:join)
                  pending_threads.clear

                  # Process all pending queue items
                  until queue.empty?
                    begin
                      background_message = queue.pop(true)
                      result = update.call(background_message, model)
                      model, command = normalize_update_result(result, model)
                      validate_ractor_shareable!(model, "model")
                      throw :quit if command.is_a?(Command::Exit)

                      thread = dispatch(command, queue) if command
                      pending_threads << thread if thread
                    rescue ThreadError
                      break
                    end
                  end
                end
              end

              # 3. Check for background outcomes (non-blocking)
              until queue.empty?
                begin
                  background_message = queue.pop(true)
                  result = update.call(background_message, model)
                  model, command = normalize_update_result(result, model)
                  validate_ractor_shareable!(model, "model")
                  throw :quit if command.is_a?(Command::Exit)

                  thread = dispatch(command, queue) if command
                  pending_threads << thread if thread
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

      # Detects whether +result+ is a +[model, command]+ tuple, a plain model, or a Command alone.
      #
      # Returns +[model, command]+ in all cases.
      private_class_method def self.normalize_update_result(result, previous_model)
        return result if result.is_a?(Array) && result.size == 2 && valid_command?(result[1])
        return [previous_model, result] if valid_command?(result)

        [result, nil]
      end

      # Returns +true+ if +value+ is a valid command (+nil+ or a +Command+ type).
      private_class_method def self.valid_command?(value)
        value.nil? || value.class.name&.start_with?("RatatuiRuby::Tea::Command::")
      end

      # Validates an object is Ractor-shareable (deeply frozen).
      #
      # Models and messages must be shareable for future Ractor support.
      # Mutable objects cause race conditions. Freeze your data.
      #
      # Only enforced in debug mode (and tests). Production skips this check
      # for performance; mutable objects will still cause bugs, but silently.
      private_class_method def self.validate_ractor_shareable!(object, name)
        return unless RatatuiRuby::Debug.enabled?
        return if Ractor.shareable?(object)

        raise RatatuiRuby::Error::Invariant,
          "#{name.capitalize} is not Ractor-shareable. Use Ractor.make_shareable or Object#freeze."
      end

      # Dispatches a command asynchronously. :nodoc:
      #
      # Spawns a background thread and pushes results to the message queue.
      # See Command.system for message formats.
      private_class_method def self.dispatch(command, queue)
        case command
        when Command::System
          Thread.new do
            require "open3"
            if command.stream?
              begin
                Open3.popen3(command.command) do |stdin, stdout, stderr, wait_thr|
                  stdin.close
                  stdout_thread = Thread.new do
                    stdout.each_line do |line|
                      queue << Ractor.make_shareable([command.tag, :stdout, line])
                    end
                  end
                  stderr_thread = Thread.new do
                    stderr.each_line do |line|
                      queue << Ractor.make_shareable([command.tag, :stderr, line])
                    end
                  end
                  stdout_thread.join
                  stderr_thread.join
                  status = wait_thr.value.exitstatus
                  queue << Ractor.make_shareable([command.tag, :complete, { status: }])
                end
              rescue Errno::ENOENT, Errno::EACCES => e
                queue << Ractor.make_shareable([command.tag, :error, { message: e.message }])
              end
            else
              stdout, stderr, status = Open3.capture3(command.command)
              message = [command.tag, { stdout:, stderr:, status: status.exitstatus }]
              queue << Ractor.make_shareable(message)
            end
          end
        when Command::Mapped
          inner_queue = Queue.new
          inner_thread = dispatch(command.inner_command, inner_queue)
          Thread.new do
            inner_thread&.join
            inner_message = inner_queue.pop
            transformed = command.mapper.call(inner_message)
            queue << Ractor.make_shareable(transformed)
          end
        end
      end
    end
  end
end

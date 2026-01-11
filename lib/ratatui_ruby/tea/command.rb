# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require_relative "command/cancellation_token"
require_relative "command/custom"
require_relative "command/outlet"

module RatatuiRuby
  module Tea
    # Commands represent side effects.
    #
    # The MVU pattern separates logic from effects. Your update function returns a pure
    # model transformation. Side effects go in commands. The runtime executes them.
    #
    # Commands produce **messages**, not callbacks. The +tag+ argument names the message
    # so your update function can pattern-match on it. This keeps all logic in +update+
    # and ensures messages are Ractor-shareable.
    #
    # === Examples
    #
    #   # Terminate the application
    #   [model, Command.exit]
    #
    #   # Run a shell command; produces [:got_files, {stdout:, stderr:, status:}]
    #   [model, Command.system("ls -la", :got_files)]
    #
    #   # No side effect
    #   [model, nil]
    module Command
      # Sentinel value for application termination.
      #
      # The runtime detects this before dispatching. It breaks the loop immediately.
      Exit = Data.define

      # Creates a quit command.
      #
      # Returns a sentinel the runtime detects to terminate the application.
      #
      # === Example
      #
      #   def update(message, model)
      #     case message
      #     in { type: :key, code: "q" }
      #       [model, Command.exit]
      #     else
      #       [model, nil]
      #     end
      #   end
      def self.exit
        Exit.new
      end

      # Sentinel value for command cancellation.
      #
      # Long-running commands (WebSocket listeners, database pollers) run until stopped.
      # Stopping them requires signaling from outside the command. The runtime tracks
      # active commands by their object identity and routes cancel requests.
      #
      # This type carries the handle (command object) to cancel. The runtime pattern-matches
      # on <tt>Command::Cancel</tt> and signals the token.
      Cancel = Data.define(:handle)

      # Request cancellation of a running command.
      #
      # The model stores the command handle (the command object itself). Returning
      # <tt>Command.cancel(handle)</tt> signals the runtime to stop it.
      #
      # [handle] The command object to cancel.
      #
      # === Example
      #
      #   # Dispatch and store handle
      #   cmd = FetchData.new(url)
      #   [model.with(active_fetch: cmd), cmd]
      #
      #   # User clicks cancel
      #   when :cancel_clicked
      #     [model.with(active_fetch: nil), Command.cancel(model.active_fetch)]
      def self.cancel(handle)
        Cancel.new(handle:)
      end

      # Command to run a shell command via Open3.
      #
      # The runtime executes the command and produces messages. In batch mode
      # (default), a single message arrives: <tt>[tag, {stdout:, stderr:, status:}]</tt>.
      #
      # In streaming mode, messages arrive incrementally:
      # - <tt>[tag, :stdout, line]</tt> for each stdout line
      # - <tt>[tag, :stderr, line]</tt> for each stderr line
      # - <tt>[tag, :complete, {status:}]</tt> when the command finishes
      # - <tt>[tag, :error, {message:}]</tt> if the command cannot start
      #
      # The <tt>status</tt> is the integer exit code (0 = success).
      System = Data.define(:command, :tag, :stream) do
        # Returns true if streaming mode is enabled.
        def stream?
          stream
        end
      end

      # Creates a shell execution command.
      #
      # [command] Shell command string to execute.
      # [tag] Symbol or class to tag the result message.
      # [stream] If <tt>true</tt>, the runtime sends incremental stdout/stderr
      #   messages as they arrive. If <tt>false</tt> (default), waits for
      #   completion and sends a single message with all output.
      #
      # === Example (Batch Mode)
      #
      #   # Return this from update:
      #   [model.with(loading: true), Command.system("ls -la", :got_files)]
      #
      #   # Then handle it later:
      #   def update(message, model)
      #     case message
      #     in [:got_files, {stdout:, status: 0}]
      #       [model.with(files: stdout.lines), nil]
      #     in [:got_files, {stderr:, status:}]
      #       [model.with(error: stderr), nil]
      #     end
      #   end
      #
      # === Example (Streaming Mode)
      #
      #   # Return this from update:
      #   [model.with(loading: true), Command.system("tail -f log.txt", :log, stream: true)]
      #
      #   # Then handle incremental messages:
      #   def update(message, model)
      #     case message
      #     in [:log, :stdout, line]
      #       [model.with(lines: [*model.lines, line]), nil]
      #     in [:log, :stderr, line]
      #       [model.with(errors: [*model.errors, line]), nil]
      #     in [:log, :complete, {status:}]
      #       [model.with(loading: false, exit_status: status), nil]
      #     in [:log, :error, {message:}]
      #       [model.with(loading: false, error: message), nil]
      #     end
      #   end
      def self.system(command, tag, stream: false)
        System.new(command:, tag:, stream:)
      end

      # Command that wraps another command's result with a transformation.
      #
      # Fractal Architecture requires composition. Child bags produce commands.
      # Parent bags route child results back to themselves. +Mapped+ wraps a
      # child bag's command and transforms its result message into a parent message.
      Mapped = Data.define(:inner_command, :mapper)

      # Creates a mapped command for Fractal Architecture composition.
      #
      # Wraps an inner command. When the inner command completes, the +mapper+ block
      # transforms the result into a parent message. This prevents monolithic update
      # functions (the "God Reducer" anti-pattern).
      #
      # [inner_command] The child command to wrap.
      # [mapper] Block that transforms child message to parent message.
      #
      # === Example
      #
      #   # Child returns Command.execute that produces [:got_files, {...}]
      #   child_command = Command.system("ls", :got_files)
      #
      #   # Parent wraps to route as [:sidebar, :got_files, {...}]
      #   parent_command = Command.map(child_command) { |child_result| [:sidebar, *child_result] }
      def self.map(inner_command, &mapper)
        Mapped.new(inner_command:, mapper:)
      end

      # Gives a callable unique identity for cancellation.
      #
      # Reusable procs and lambdas share identity. Dispatch them twice, and
      # +Command.cancel+ would cancel both. Wrap them to get distinct handles.
      #
      # [callable] Proc, lambda, or any object responding to +call(out, token)+.
      #            If omitted, the block is used.
      # [grace_period] Cleanup time override. Default: 2.0 seconds.
      #
      # === Example
      #
      #   # With callable
      #   cmd = Command.custom(->(out, token) { out.put(:fetched, data) })
      #
      #   # With block
      #   cmd = Command.custom(grace_period: 5.0) do |out, token|
      #     until token.cancelled?
      #       out.put(:tick, Time.now)
      #       sleep 1
      #     end
      #   end
      def self.custom(callable = nil, grace_period: nil, &block)
        Wrapped.new(callable: callable || block, grace_period:)
      end

      # :nodoc:
      Wrapped = Data.define(:callable, :grace_period) do
        include Custom
        def tea_cancellation_grace_period = grace_period || super
        def call(out, token) = callable.call(out, token)
      end
      private_constant :Wrapped
    end
  end
end

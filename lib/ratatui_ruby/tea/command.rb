# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

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

      # Command to run a shell command via Open3.
      #
      # The runtime executes the command and produces a message:
      # <tt>[tag, {stdout:, stderr:, status:}]</tt>
      #
      # The +status+ is the integer exit code (0 = success).
      System = Data.define(:command, :tag)

      # Creates a shell execution command.
      #
      # [command] Shell command string to execute.
      # [tag] Symbol or class to tag the result message.
      #
      # When the command completes, the runtime sends
      # <tt>[tag, {stdout:, stderr:, status:}]</tt> to update.
      #
      # === Example
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
      def self.system(command, tag)
        System.new(command:, tag:)
      end

      # Command that wraps another command's result with a transformation.
      #
      # Fractal Architecture requires composition. Child components produce commands.
      # Parent components need to route child results back to themselves. +Mapped+
      # wraps a child command and transforms its result message into a parent message.
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
    end
  end
end

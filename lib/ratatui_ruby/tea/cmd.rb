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
    #   [model, Cmd.quit]
    #
    #   # Run a shell command; produces [:got_files, {stdout:, stderr:, status:}]
    #   [model, Cmd.exec("ls -la", :got_files)]
    #
    #   # No side effect
    #   [model, nil]
    module Cmd
      # Sentinel value for application termination.
      #
      # The runtime detects this before dispatching. It breaks the loop immediately.
      Quit = Data.define

      # Creates a quit command.
      #
      # Returns a sentinel the runtime detects to terminate the application.
      #
      # === Example
      #
      #   def update(msg, model)
      #     case msg
      #     in { type: :key, code: "q" }
      #       [model, Cmd.quit]
      #     else
      #       [model, nil]
      #     end
      #   end
      def self.quit
        Quit.new
      end

      # Command to run a shell command via Open3.
      #
      # The runtime executes the command and produces a message:
      # <tt>[tag, {stdout:, stderr:, status:}]</tt>
      #
      # The +status+ is the integer exit code (0 = success).
      Exec = Data.define(:command, :tag)

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
      #   [model.with(loading: true), Cmd.exec("ls -la", :got_files)]
      #
      #   # Then handle it later:
      #   def update(msg, model)
      #     case msg
      #     in [:got_files, {stdout:, status: 0}]
      #       [model.with(files: stdout.lines), nil]
      #     in [:got_files, {stderr:, status:}]
      #       [model.with(error: stderr), nil]
      #     end
      #   end
      def self.exec(command, tag)
        Exec.new(command:, tag:)
      end

      # Wraps a command to transform its result message.
      Mapped = Data.define(:inner_cmd, :mapper)

      # Creates a mapped command.
      def self.map(inner_cmd, &mapper)
        Mapped.new(inner_cmd:, mapper:)
      end
    end
  end
end

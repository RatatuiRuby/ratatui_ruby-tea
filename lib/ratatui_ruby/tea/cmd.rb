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
    # Use commands to quit the application, run shell commands, or fetch data.
    #
    # === Examples
    #
    #   # Terminate the application
    #   [model, Cmd.quit]
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
    end
  end
end

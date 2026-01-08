# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require_relative "command"

module RatatuiRuby
  module Tea
    # Convenient short aliases for Tea APIs.
    #
    # The library uses intention-revealing names that match Ruby built-ins:
    # +Command+, +System+, +Exit+. These are great for readability.
    #
    # This module provides the short aliases common in TEA-style code:
    #
    # === Example
    #
    #   require "ratatui_ruby/tea/shortcuts"
    #   include RatatuiRuby::Tea::Shortcuts
    #
    #   # Now use short names freely:
    #   Cmd.exit               # → Command.exit
    #   Cmd.sh("ls", :files)   # → Command.system("ls", :files)
    #   Cmd.map(child) { ... } # → Command.map(child) { ... }
    module Shortcuts
      # Short alias for +Command+.
      module Cmd
        # Creates an exit command.
        # Alias for +Command.exit+.
        def self.exit
          Command.exit
        end

        # Creates a shell execution command.
        # Short alias for +Command.system+.
        def self.sh(command, tag)
          Command.system(command, tag)
        end

        # Creates a mapped command.
        # Short alias for +Command.map+.
        def self.map(inner_command, &mapper)
          Command.map(inner_command, &mapper)
        end
      end
    end
  end
end

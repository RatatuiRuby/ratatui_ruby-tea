# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

module RatatuiRuby
  module Tea
    module Command
      # Mixin for user-defined custom commands.
      #
      # Custom commands extend Tea with side effects: WebSockets, gRPC, database polls,
      # background tasks. The runtime dispatches them in threads and routes results
      # back as messages.
      #
      # Include this module to identify your class as a command. The runtime uses
      # +tea_command?+ to distinguish commands from plain models. Override
      # +tea_cancellation_grace_period+ if your cleanup takes longer than two seconds.
      #
      # Use it to build real-time features, long-polling connections, or background workers.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-FileCopyrightText: 2026 Kerrick Long
      # SPDX-License-Identifier: MIT-0
      #++
      #   class WebSocketCommand
      #     include RatatuiRuby::Tea::Command::Custom
      #
      #     def initialize(url)
      #       @url = url
      #     end
      #
      #     def call(out, token)
      #       ws = WebSocket::Client.new(@url)
      #       ws.on_message { |msg| out.put(:ws_message, msg) }
      #       ws.connect
      #
      #       until token.cancelled?
      #         ws.ping
      #         sleep 1
      #       end
      #
      #       ws.close
      #     end
      #
      #     # WebSocket close handshake needs extra time
      #     def tea_cancellation_grace_period
      #       5.0
      #     end
      #   end
      #--
      # SPDX-SnippetEnd
      #++
      module Custom
        # Brand predicate for command identification.
        #
        # The runtime calls this to distinguish commands from plain models.
        # Returns <tt>true</tt> unconditionally.
        #
        # You do not need to override this method.
        def tea_command?
          true
        end

        # Cleanup time after cancellation is requested. In seconds.
        #
        # When the runtime cancels your command (app exit, navigation, explicit cancel),
        # it calls <tt>token.cancel!</tt> and waits this long for your command to stop.
        # If your command does not exit within this window, it is force-killed.
        #
        # *This is NOT a lifetime limit.* Your command runs indefinitely until cancelled.
        # A WebSocket open for 15 minutes is fine. This timeout only applies to the
        # cleanup phase after cancellation is requested.
        #
        # Override this method to specify how long your cleanup takes:
        #
        # - <tt>0.5</tt> — Quick HTTP abort, no cleanup needed
        # - <tt>2.0</tt> — Default, suitable for most commands
        # - <tt>5.0</tt> — WebSocket close handshake with remote server
        # - <tt>Float::INFINITY</tt> — Never force-kill (database transactions)
        #
        # === Example
        #
        #--
        # SPDX-SnippetBegin
        # SPDX-FileCopyrightText: 2026 Kerrick Long
        # SPDX-License-Identifier: MIT-0
        #++
        #   # Database transactions should never be interrupted mid-write
        #   def tea_cancellation_grace_period
        #     Float::INFINITY
        #   end
        #--
        # SPDX-SnippetEnd
        #++
        def tea_cancellation_grace_period
          2.0
        end
      end
    end
  end
end

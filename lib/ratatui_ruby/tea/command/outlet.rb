# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "ratatui_ruby"

module RatatuiRuby
  module Tea
    module Command
      # Messaging gateway for custom commands.
      #
      # Custom commands run in background threads. They produce results that the
      # main loop consumes.
      #
      # Managing queues and message formats manually is tedious. It scatters queue
      # logic across your codebase and makes mistakes easy.
      #
      # This class wraps the queue with a clean API. Call +put+ to send tagged
      # messages. Debug mode validates Ractor-shareability.
      #
      # Use it to send results from HTTP requests, WebSocket streams, or database polls.
      #
      # === Example (One-Shot)
      #
      # Commands run in their own thread. Blocking calls work fine:
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-FileCopyrightText: 2026 Kerrick Long
      # SPDX-License-Identifier: MIT-0
      #++
      #   class FetchUserCommand
      #     include Tea::Command::Custom
      #
      #     def initialize(user_id)
      #       @user_id = user_id
      #     end
      #
      #     def call(out, _token)
      #       response = Net::HTTP.get(URI("https://api.example.com/users/#{@user_id}"))
      #       user = JSON.parse(response)
      #       out.put(:user_fetched, Ractor.make_shareable(user: user))
      #     rescue => e
      #       out.put(:user_fetch_failed, error: e.message.freeze)
      #     end
      #   end
      #--
      # SPDX-SnippetEnd
      #++
      #
      # === Example (Long-Running)
      #
      # Commands that loop check the cancellation token:
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-FileCopyrightText: 2026 Kerrick Long
      # SPDX-License-Identifier: MIT-0
      #++
      #   class PollerCommand
      #     include Tea::Command::Custom
      #
      #     def call(out, token)
      #       until token.cancelled?
      #         data = fetch_batch
      #         out.put(:batch, Ractor.make_shareable(data))
      #         sleep 5
      #       end
      #       out.put(:poller_stopped)
      #     end
      #   end
      #--
      # SPDX-SnippetEnd
      #++
      class Outlet
        # Creates an outlet for the given queue.
        #
        # The runtime provides the queue. Custom commands receive the outlet as
        # their first argument.
        #
        # [queue] A <tt>Thread::Queue</tt> or compatible object.
        def initialize(queue)
          @queue = queue
        end

        # Sends a tagged message to the runtime.
        #
        # Builds an array <tt>[tag, *payload]</tt> and pushes it to the queue.
        # The update function pattern-matches on the tag.
        #
        # Debug mode validates Ractor-shareability. It raises <tt>Error::Invariant</tt>
        # if the message is not shareable. Production skips this check.
        #
        # [tag] Symbol identifying the message type.
        # [payload] Additional arguments. Freeze them or use <tt>Ractor.make_shareable</tt>.
        #
        # === Example
        #
        #--
        # SPDX-SnippetBegin
        # SPDX-FileCopyrightText: 2026 Kerrick Long
        # SPDX-License-Identifier: MIT-0
        #++
        #   out.put(:user_fetched, user: Ractor.make_shareable(user))
        #   out.put(:error, message: "Connection failed".freeze)
        #   out.put(:progress, percent: 42)  # Integers are always shareable
        #--
        # SPDX-SnippetEnd
        #++
        def put(tag, *payload)
          message = [tag, *payload].freeze

          if RatatuiRuby::Debug.enabled? && !Ractor.shareable?(message)
            raise RatatuiRuby::Error::Invariant,
              "Message is not Ractor-shareable: #{message.inspect}\n" \
                "Use Ractor.make_shareable or Object#freeze."
          end

          @queue << message
        end
      end
    end
  end
end

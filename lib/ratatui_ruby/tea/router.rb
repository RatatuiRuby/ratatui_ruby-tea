# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

module RatatuiRuby
  module Tea
    # Declarative DSL for Fractal Architecture.
    #
    # Large applications decompose into bags. Each bag has its own Model,
    # UPDATE, and VIEW. Parent bags route messages to child bags and compose views.
    # Writing this routing logic by hand is tedious and error-prone.
    #
    # Include this module to declare routes and keymaps. Call +from_router+ to
    # generate an UPDATE lambda that handles routing automatically.
    #
    # A *bag* is a module containing <tt>Model</tt>, <tt>INITIAL</tt>,
    # <tt>UPDATE</tt>, and <tt>VIEW</tt> constants. Bags compose: parent bags
    # delegate to child bags.
    #
    # === Example
    #
    #   class Dashboard
    #     include Tea::Router
    #
    #     route :stats, to: StatsPanel
    #     route :network, to: NetworkPanel
    #
    #     keymap do
    #       key "s", -> { SystemInfo.fetch_command }, route: :stats
    #       key "q", -> { Command.exit }
    #     end
    #
    #     Model = Data.define(:stats, :network)
    #     INITIAL = Model.new(stats: StatsPanel::INITIAL, network: NetworkPanel::INITIAL)
    #     VIEW = ->(model, tui) { ... }
    #     UPDATE = from_router
    #   end
    module Router
      # :nodoc:
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Class methods added when Router is included.
      module ClassMethods
        # Declares a route to a child.
        #
        # [prefix] Symbol or String identifying the route (normalized via +.to_s.to_sym+).
        # [to] The child module (must have UPDATE and INITIAL constants).
        def route(prefix, to:)
          routes[prefix.to_s.to_sym] = to
        end

        # Returns the registered routes hash.
        def routes
          @routes ||= {}
        end

        # Declares a named action.
        #
        # Actions are shared handlers that keymap and mousemap can reference.
        # This avoids duplicating logic for keys and mouse events that do
        # the same thing.
        #
        # [name] Symbol or String identifying the action (normalized via +.to_s.to_sym+).
        # [handler] Callable that returns a command or message.
        def action(name, handler)
          actions[name.to_s.to_sym] = handler
        end

        # Returns the registered actions hash.
        def actions
          @actions ||= {}
        end

        # Declares key handlers in a block.
        #
        # === Example
        #
        #   keymap do
        #     key "q", -> { Command.exit }
        #     key :up, :scroll_up  # Delegate to action
        #   end
        def keymap(&)
          builder = KeymapBuilder.new
          builder.instance_eval(&)
          @key_handlers = builder.handlers
        end

        # Returns the registered key handlers hash.
        def key_handlers
          @key_handlers ||= {}
        end

        # Declares mouse handlers in a block.
        #
        # === Example
        #
        #   mousemap do
        #     click -> (x, y) { [:clicked, x, y] }
        #     scroll :up, :scroll_up  # Delegate to action
        #   end
        def mousemap(&)
          builder = MousemapBuilder.new
          builder.instance_eval(&)
          @mouse_handlers = builder.handlers
        end

        # Returns the registered mouse handlers hash.
        def mouse_handlers
          @mouse_handlers ||= {}
        end

        # Generates an UPDATE lambda from routes, keymap, and mousemap.
        #
        # The generated UPDATE:
        # 1. Routes prefixed messages to child UPDATEs
        # 2. Handles keyboard events via keymap
        # 3. Handles mouse events via mousemap
        # 4. Returns model unchanged for unhandled messages
        def from_router
          my_routes = routes
          my_actions = actions
          my_key_handlers = key_handlers
          my_mouse_handlers = mouse_handlers

          lambda do |message, model|
            # 1. Try routing prefixed messages to children
            my_routes.each do |prefix, child|
              result = Tea.delegate(message, prefix, child::UPDATE, model.public_send(prefix))
              if result
                new_child, command = result
                return [model.with(prefix => new_child), command]
              end
            end

            # 2. Try keymap handlers (message is an Event)
            if message.respond_to?(:key?) && message.key?
              my_key_handlers.each do |key_name, config|
                predicate = :"#{key_name}?"
                next unless message.respond_to?(predicate) && message.public_send(predicate)

                handler = config[:handler] || my_actions[config[:action]]
                command = handler.call
                if config[:route]
                  command = Tea.route(command, config[:route])
                end
                return [model, command]
              end
            end

            # 3. Try mousemap handlers
            if message.respond_to?(:mouse?) && message.mouse?
              # Scroll events
              if message.respond_to?(:scroll_up?) && message.scroll_up?
                config = my_mouse_handlers[:scroll_up]
                if config
                  handler = config[:handler] || my_actions[config[:action]]
                  return [model, handler.call]
                end
              end
              if message.respond_to?(:scroll_down?) && message.scroll_down?
                config = my_mouse_handlers[:scroll_down]
                if config
                  handler = config[:handler] || my_actions[config[:action]]
                  return [model, handler.call]
                end
              end
              # Click events
              if message.respond_to?(:click?) && message.click?
                config = my_mouse_handlers[:click]
                if config
                  handler = config[:handler] || my_actions[config[:action]]
                  return [model, handler.call(message.x, message.y)]
                end
              end
            end

            # 4. Unhandled - return model unchanged
            [model, nil]
          end
        end
      end

      # Builder for keymap DSL.
      class KeymapBuilder
        # Returns the registered handlers hash.
        attr_reader :handlers

        # :nodoc:
        def initialize
          @handlers = {}
        end

        # Registers a key handler.
        #
        # [key_name] String or Symbol for the key (normalized via +.to_s+).
        # [handler_or_action] Callable or Symbol (action name).
        # [route] Optional route prefix for the command result.
        def key(key_name, handler_or_action, route: nil)
          entry = {}
          if handler_or_action.is_a?(Symbol)
            entry[:action] = handler_or_action
          else
            entry[:handler] = handler_or_action
          end
          entry[:route] = route if route
          @handlers[key_name.to_s] = entry
        end
      end

      # Builder for mousemap DSL.
      class MousemapBuilder
        # Returns the registered handlers hash.
        attr_reader :handlers

        # :nodoc:
        def initialize
          @handlers = {}
        end

        # Registers a click handler.
        #
        # [handler_or_action] Callable or Symbol (action name).
        def click(handler_or_action)
          register(:click, handler_or_action)
        end

        # Registers a scroll handler.
        #
        # [direction] <tt>:up</tt> or <tt>:down</tt>.
        # [handler_or_action] Callable or Symbol (action name).
        def scroll(direction, handler_or_action)
          register(:"scroll_#{direction}", handler_or_action)
        end

        private def register(key, handler_or_action)
          entry = {}
          if handler_or_action.is_a?(Symbol)
            entry[:action] = handler_or_action
          else
            entry[:handler] = handler_or_action
          end
          @handlers[key] = entry
        end
      end
    end
  end
end

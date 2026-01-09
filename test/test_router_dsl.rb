# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"

class TestRouterDsl < Minitest::Test
  # Fake child module for testing
  module FakeChild
    INITIAL = :child_initial
    UPDATE = -> (msg, model) { [model, nil] }
  end

  # route registers a child with a prefix.
  # The prefix is normalized to a symbol via .to_s.to_sym.
  def test_route_registers_child_with_prefix
    test_class = Class.new do
      include RatatuiRuby::Tea::Router

      route :stats, to: TestRouterDsl::FakeChild
      route "network", to: TestRouterDsl::FakeChild # String works too
    end

    assert_equal FakeChild, test_class.routes[:stats]
    assert_equal FakeChild, test_class.routes[:network]
  end

  # action defines a named action that can be referenced by keymap/mousemap.
  # Actions are normalized via .to_s.to_sym.
  def test_action_defines_named_action
    handler = -> { [:scroll, -1] }

    test_class = Class.new do
      include RatatuiRuby::Tea::Router

      action :scroll_up, handler
      action "scroll_down", -> { [:scroll, 1] } # String works too
    end

    assert_equal handler, test_class.actions[:scroll_up]
    assert test_class.actions[:scroll_down].is_a?(Proc)
  end

  # keymap registers key handlers.
  # Keys are normalized via .to_s.
  def test_keymap_registers_key_handlers
    handler = -> { Command.exit }

    test_class = Class.new do
      include RatatuiRuby::Tea::Router

      keymap do
        key "q", handler
        key :ctrl_c, handler # Symbol works
        key "s", -> { :fetch }, route: :stats
      end
    end

    assert_equal handler, test_class.key_handlers["q"][:handler]
    assert_equal handler, test_class.key_handlers["ctrl_c"][:handler]
    assert_equal :stats, test_class.key_handlers["s"][:route]
  end

  # keymap allows delegation to named actions.
  def test_keymap_delegates_to_action
    test_class = Class.new do
      include RatatuiRuby::Tea::Router

      action :scroll_up, -> { [:scroll, -1] }

      keymap do
        key :up, :scroll_up # Delegate to action
      end
    end

    assert_equal :scroll_up, test_class.key_handlers["up"][:action]
  end

  # mousemap registers mouse handlers.
  def test_mousemap_registers_mouse_handlers
    click_handler = -> (x, y) { [:clicked, x, y] }

    test_class = Class.new do
      include RatatuiRuby::Tea::Router

      mousemap do
        click click_handler
        scroll :up, -> { [:scroll, -1] }
        scroll :down, -> { [:scroll, 1] }
      end
    end

    assert_equal click_handler, test_class.mouse_handlers[:click][:handler]
    assert test_class.mouse_handlers[:scroll_up][:handler].is_a?(Proc)
    assert test_class.mouse_handlers[:scroll_down][:handler].is_a?(Proc)
  end

  # mousemap allows delegation to named actions.
  def test_mousemap_delegates_to_action
    test_class = Class.new do
      include RatatuiRuby::Tea::Router

      action :scroll_up, -> { [:scroll, -1] }

      mousemap do
        scroll :up, :scroll_up # Delegate to action
      end
    end

    assert_equal :scroll_up, test_class.mouse_handlers[:scroll_up][:action]
  end

  # from_router returns a callable UPDATE lambda
  def test_from_router_returns_callable
    test_class = Class.new do
      include RatatuiRuby::Tea::Router
    end

    update = test_class.from_router

    assert update.respond_to?(:call)
  end

  # Generated UPDATE routes prefixed messages to child UPDATE
  def test_from_router_routes_prefixed_messages
    # FakeChild is defined at class level with proper UPDATE constant
    test_class = Class.new do
      include RatatuiRuby::Tea::Router
      route :child, to: TestRouterDsl::FakeChild
    end

    update = test_class.from_router

    # Create a model with a :child accessor (using Data.define)
    model_class = Data.define(:child)
    model = model_class.new(child: { output: "initial" }.freeze)

    message = [:child, :system_info, { stdout: "Darwin" }]

    new_model, _cmd = update.call(message, model)

    # Verify it delegated and returned updated model
    refute_nil new_model
  end

  # keymap key accepts when: guard that prevents handler execution when false
  def test_keymap_key_when_guard_prevents_execution
    handler_called = false
    guard_proc = -> (model) { model[:allowed] }

    test_class = Class.new do
      include RatatuiRuby::Tea::Router

      keymap do
        key "x", -> { handler_called = true; nil }, when: guard_proc
      end
    end

    update = test_class.from_router

    model = { allowed: false }.freeze
    event = RatatuiRuby::Event::Key.new(code: "x")

    _new_model, _cmd = update.call(event, model)

    refute handler_called, "Handler should not be called when guard returns false"
  end

  # when: guard allows handler execution when true
  def test_keymap_key_when_guard_allows_execution
    handler_called = false
    guard_proc = -> (model) { model[:allowed] }

    test_class = Class.new do
      include RatatuiRuby::Tea::Router

      keymap do
        key "x", -> { handler_called = true; nil }, when: guard_proc
      end
    end

    update = test_class.from_router

    model = { allowed: true }.freeze
    event = RatatuiRuby::Event::Key.new(code: "x")

    _new_model, _cmd = update.call(event, model)

    assert handler_called, "Handler should be called when guard returns true"
  end

  # if: is an alias for when:
  def test_keymap_key_if_alias_for_when
    handler_called = false
    guard_proc = -> (model) { model[:allowed] }

    test_class = Class.new do
      include RatatuiRuby::Tea::Router

      keymap do
        key "x", -> { handler_called = true; nil }, if: guard_proc
      end
    end

    update = test_class.from_router

    model = { allowed: false }.freeze
    event = RatatuiRuby::Event::Key.new(code: "x")

    _new_model, _cmd = update.call(event, model)

    refute handler_called, "Handler should not be called when if: guard returns false"
  end

  # unless: is a negative alias (runs when guard is false)
  def test_keymap_key_unless_runs_when_guard_false
    handler_called = false
    guard_proc = -> (model) { model[:blocked] }

    test_class = Class.new do
      include RatatuiRuby::Tea::Router

      keymap do
        key "x", -> { handler_called = true; nil }, unless: guard_proc
      end
    end

    update = test_class.from_router

    model = { blocked: false }.freeze
    event = RatatuiRuby::Event::Key.new(code: "x")

    _new_model, _cmd = update.call(event, model)

    assert handler_called, "Handler should run when unless: guard returns false"
  end
end

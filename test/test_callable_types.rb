# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"
require "ratatui_ruby/test_helper"

# Documents that procs, lambdas, Method objects, and service objects all work
# as callable parameters for the Tea runtime.
class TestCallableTypes < Minitest::Test
  include RatatuiRuby::TestHelper

  def test_procs_work_as_view_and_update
    model = Ractor.make_shareable({ text: "hello" })
    view_called = false
    update_called = false

    view = proc do |_model, tui|
      view_called = true
      tui.clear
    end

    update = proc do |_message, current_model|
      update_called = true
      [current_model, RatatuiRuby::Tea::Cmd.quit]
    end

    with_test_terminal do
      inject_key("q")
      RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
    end

    assert view_called, "proc should work as view"
    assert update_called, "proc should work as update"
  end

  def test_lambdas_work_as_view_and_update
    model = Ractor.make_shareable({ text: "hello" })
    view_called = false
    update_called = false

    view = lambda do |_model, tui|
      view_called = true
      tui.clear
    end

    update = lambda do |_message, current_model|
      update_called = true
      [current_model, RatatuiRuby::Tea::Cmd.quit]
    end

    with_test_terminal do
      inject_key("q")
      RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
    end

    assert view_called, "lambda should work as view"
    assert update_called, "lambda should work as update"
  end

  def view_method(_model, tui)
    @view_method_called = true
    tui.clear
  end

  def update_method(_message, current_model)
    @update_method_called = true
    [current_model, RatatuiRuby::Tea::Cmd.quit]
  end

  def test_method_objects_work_as_view_and_update
    model = Ractor.make_shareable({ text: "hello" })
    @view_method_called = false
    @update_method_called = false

    with_test_terminal do
      inject_key("q")
      RatatuiRuby::Tea::Runtime.run(
        model:,
        view: method(:view_method),
        update: method(:update_method)
      )
    end

    assert @view_method_called, "Method object should work as view"
    assert @update_method_called, "Method object should work as update"
  end

  # Functional objects: any object responding to #call

  class MyView
    attr_reader :called

    def initialize
      @called = false
    end

    def call(_model, tui)
      @called = true
      tui.clear
    end
  end

  class MyUpdate
    attr_reader :called

    def initialize
      @called = false
    end

    def call(_message, current_model)
      @called = true
      [current_model, RatatuiRuby::Tea::Cmd.quit]
    end
  end

  def test_service_objects_work_as_view_and_update
    model = Ractor.make_shareable({ text: "hello" })
    view = MyView.new
    update = MyUpdate.new

    with_test_terminal do
      inject_key("q")
      RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
    end

    assert view.called, "service object should work as view"
    assert update.called, "service object should work as update"
  end
end

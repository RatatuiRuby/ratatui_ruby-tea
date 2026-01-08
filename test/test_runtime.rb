# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"
require "ratatui_ruby/test_helper"

class TestRuntime < Minitest::Test
  include RatatuiRuby::TestHelper

  def test_runtime_class_exists
    assert_kind_of Class, RatatuiRuby::Tea::Runtime
  end

  def test_runtime_responds_to_run
    assert_respond_to RatatuiRuby::Tea::Runtime, :run
  end

  def test_view_receives_model_and_tui
    model = { text: "hello" }.freeze
    view_args = nil

    view = -> (m, t) { view_args = [m, t]; nil }
    update = -> (msg, _m) { [model, RatatuiRuby::Tea::Cmd.quit] }

    with_test_terminal do
      RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
    end

    assert_equal model, view_args[0], "view should receive model as first arg"
    assert_kind_of RatatuiRuby::TUI, view_args[1], "view should receive TUI as second arg"
  end
end

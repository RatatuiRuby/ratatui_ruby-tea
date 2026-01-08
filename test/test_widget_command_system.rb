# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require "test_helper"
$LOAD_PATH.unshift File.expand_path("../examples/widget_command_system", __dir__)
require "app"

class TestWidgetCommandSystem < Minitest::Test
  def test_update_handles_successful_exec_result
    model = WidgetCommandSystem::INITIAL
    msg = [:got_output, { stdout: "file1\nfile2\n", stderr: "", status: 0 }]

    result = WidgetCommandSystem::UPDATE.call(msg, model)

    assert_kind_of Array, result
    new_model, cmd = result
    assert_equal "file1\nfile2", new_model.result
    refute new_model.loading
    assert_nil cmd
    assert Ractor.shareable?(new_model), "New model should be Ractor-shareable"
  end

  def test_update_handles_failed_exec_result
    model = WidgetCommandSystem::INITIAL
    msg = [:got_output, { stdout: "", stderr: "No such file\n", status: 1 }]

    result = WidgetCommandSystem::UPDATE.call(msg, model)

    new_model, cmd = result
    assert_includes new_model.result, "Error (exit 1)"
    assert_includes new_model.result, "No such file"
    refute new_model.loading
    assert_nil cmd
    assert Ractor.shareable?(new_model), "New model should be Ractor-shareable"
  end
end

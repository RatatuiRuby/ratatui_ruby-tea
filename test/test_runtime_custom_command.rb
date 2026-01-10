# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"
require "ratatui_ruby/test_helper"

class TestRuntimeCustomCommand < Minitest::Test
  include RatatuiRuby::TestHelper

  def test_normalize_update_result_recognizes_custom_command
    command_class = Class.new do
      include RatatuiRuby::Tea::Command::Custom
    end

    command = command_class.new
    previous_model = :old_model

    # Simulate update returning [model, custom_command]
    result = [:new_model, command]
    normalized = RatatuiRuby::Tea::Runtime.__send__(:normalize_update_result, result, previous_model)

    assert_equal :new_model, normalized[0], "Model should be extracted"
    assert_equal command, normalized[1], "Custom command should be recognized as command"
  end

  def test_dispatch_calls_custom_command_with_outlet_and_token
    received_out = nil
    received_token = nil

    command_class = Class.new do
      include RatatuiRuby::Tea::Command::Custom

      define_method(:initialize) do |callback|
        @callback = callback
      end

      define_method(:call) do |out, token|
        @callback.call(out, token)
      end
    end

    callback = -> (out, token) do
      received_out = out
      received_token = token
    end

    command = command_class.new(callback)
    queue = Queue.new

    thread = RatatuiRuby::Tea::Runtime.__send__(:dispatch, command, queue)
    thread&.join

    refute_nil received_out, "Command should have received an Outlet"
    refute_nil received_token, "Command should have received a CancellationToken"
    assert_kind_of RatatuiRuby::Tea::Command::Outlet, received_out
    assert_kind_of RatatuiRuby::Tea::Command::CancellationToken, received_token
  end

  def test_outlet_messages_arrive_in_queue
    command_class = Class.new do
      include RatatuiRuby::Tea::Command::Custom

      define_method(:call) do |out, _token|
        out.put(:test_message, :payload)
      end
    end

    command = command_class.new
    queue = Queue.new

    thread = RatatuiRuby::Tea::Runtime.__send__(:dispatch, command, queue)
    thread&.join

    message = begin
      queue.pop(true)
    rescue
      nil
    end
    refute_nil message, "Queue should have received a message"
    assert_equal [:test_message, :payload], message
  end
end

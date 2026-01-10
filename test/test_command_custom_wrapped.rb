# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"

class TestCommandCustomWrapped < Minitest::Test
  def test_custom_returns_callable_command
    callable = -> (out, token) { out.put(:done) }

    wrapped = RatatuiRuby::Tea::Command.custom(callable)

    assert wrapped.tea_command?, "Wrapped should be a custom command"
    assert_respond_to wrapped, :call
  end

  def test_wrapping_same_proc_twice_produces_distinct_objects
    shared_proc = -> (out, token) { out.put(:done) }

    wrapped_a = RatatuiRuby::Tea::Command.custom(shared_proc)
    wrapped_b = RatatuiRuby::Tea::Command.custom(shared_proc)

    refute_same wrapped_a, wrapped_b, "Each wrap should produce a distinct object"
  end

  def test_wrapped_call_delegates_to_callable
    received_args = nil
    callable = -> (out, token) { received_args = [out, token] }

    wrapped = RatatuiRuby::Tea::Command.custom(callable)
    mock_out = Object.new
    mock_token = Object.new
    wrapped.call(mock_out, mock_token)

    assert_equal [mock_out, mock_token], received_args
  end

  def test_custom_grace_period_overrides_default
    callable = -> (out, token) { out.put(:done) }

    wrapped = RatatuiRuby::Tea::Command.custom(callable, grace_period: 10.0)

    assert_equal 10.0, wrapped.tea_cancellation_grace_period
  end

  def test_default_grace_period_when_not_specified
    callable = -> (out, token) { out.put(:done) }

    wrapped = RatatuiRuby::Tea::Command.custom(callable)

    assert_equal 2.0, wrapped.tea_cancellation_grace_period
  end

  def test_custom_accepts_block
    received_args = nil

    wrapped = RatatuiRuby::Tea::Command.custom { |out, token| received_args = [out, token] }
    mock_out = Object.new
    mock_token = Object.new
    wrapped.call(mock_out, mock_token)

    assert_equal [mock_out, mock_token], received_args
  end

  # === Documentarian tests: all callable types work ===

  def test_accepts_lambda
    called = false
    cmd = RatatuiRuby::Tea::Command.custom(-> (out, token) { called = true })
    cmd.call(Object.new, Object.new)

    assert called, "Lambda should be accepted"
  end

  def test_accepts_proc
    called = false
    cmd = RatatuiRuby::Tea::Command.custom(proc { |out, token| called = true })
    cmd.call(Object.new, Object.new)

    assert called, "Proc should be accepted"
  end

  def test_accepts_method_object
    fetcher = Class.new do
      attr_reader :received

      def fetch_data(out, token)
        @received = [out, token]
      end
    end.new

    cmd = RatatuiRuby::Tea::Command.custom(fetcher.method(:fetch_data))
    mock_out = Object.new
    mock_token = Object.new
    cmd.call(mock_out, mock_token)

    assert_equal [mock_out, mock_token], fetcher.received, "Method object should be accepted"
  end

  def test_accepts_callable_instance
    fetcher = Class.new do
      attr_reader :called

      def call(out, token)
        @called = true
      end
    end.new

    cmd = RatatuiRuby::Tea::Command.custom(fetcher)
    cmd.call(Object.new, Object.new)

    assert fetcher.called, "Callable instance should be accepted"
  end
end

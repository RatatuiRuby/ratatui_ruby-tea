# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"

class TestStreamingCommand < Minitest::Test
  # Test that streaming mode produces a stdout message instead of batch hash.
  def test_streaming_command_produces_stdout_message
    queue = Queue.new
    cmd = RatatuiRuby::Tea::Command.system(
      "echo hello",
      :output,
      stream: true
    )

    RatatuiRuby::Tea::Runtime.__send__(:dispatch, cmd, queue)

    # Wait for messages with timeout
    messages = []
    start = Time.now
    loop do
      break if Time.now - start > 2

      begin
        msg = queue.pop(true)
        messages << msg
        # In streaming: expect :stdout/:stderr/:complete symbols
        # In batch: expect a Hash
        break if msg[1] == :complete || msg[1].is_a?(Hash)
      rescue ThreadError
        sleep 0.01
      end
    end

    stdout_msgs = messages.select { |m| m[1] == :stdout }
    refute_empty stdout_msgs, "Expected [:output, :stdout, ...] message, got batch mode"
  end

  def test_streaming_stdout_message_has_correct_tag
    queue = Queue.new
    cmd = RatatuiRuby::Tea::Command.system("echo hello", :my_tag, stream: true)

    RatatuiRuby::Tea::Runtime.__send__(:dispatch, cmd, queue)

    msg = nil
    start = Time.now
    loop do
      break if Time.now - start > 2

      begin
        msg = queue.pop(true)
        break if msg[1] == :stdout
      rescue ThreadError
        sleep 0.01
      end
    end

    assert_equal :my_tag, msg[0], "stdout message tag should match command tag"
  end

  def test_streaming_stdout_message_has_line_content
    queue = Queue.new
    cmd = RatatuiRuby::Tea::Command.system("echo hello", :output, stream: true)

    RatatuiRuby::Tea::Runtime.__send__(:dispatch, cmd, queue)

    msg = nil
    start = Time.now
    loop do
      break if Time.now - start > 2

      begin
        msg = queue.pop(true)
        break if msg[1] == :stdout
      rescue ThreadError
        sleep 0.01
      end
    end

    assert_equal "hello\n", msg[2], "stdout message should contain line content"
  end

  def test_streaming_command_produces_stderr_message
    queue = Queue.new
    cmd = RatatuiRuby::Tea::Command.system(
      "echo error >&2",
      :output,
      stream: true
    )

    RatatuiRuby::Tea::Runtime.__send__(:dispatch, cmd, queue)

    messages = []
    start = Time.now
    loop do
      break if Time.now - start > 2

      begin
        msg = queue.pop(true)
        messages << msg
        break if msg[1] == :complete || msg[1].is_a?(Hash)
      rescue ThreadError
        sleep 0.01
      end
    end

    stderr_msgs = messages.select { |m| m[1] == :stderr }
    refute_empty stderr_msgs, "Expected [:output, :stderr, ...] message"
  end

  def test_streaming_stderr_message_has_correct_tag
    queue = Queue.new
    cmd = RatatuiRuby::Tea::Command.system("echo error >&2", :my_tag, stream: true)

    RatatuiRuby::Tea::Runtime.__send__(:dispatch, cmd, queue)

    msg = nil
    start = Time.now
    loop do
      break if Time.now - start > 2

      begin
        msg = queue.pop(true)
        break if msg[1] == :stderr
      rescue ThreadError
        sleep 0.01
      end
    end

    assert_equal :my_tag, msg[0], "stderr message tag should match command tag"
  end

  def test_streaming_stderr_message_has_line_content
    queue = Queue.new
    cmd = RatatuiRuby::Tea::Command.system("echo error >&2", :output, stream: true)

    RatatuiRuby::Tea::Runtime.__send__(:dispatch, cmd, queue)

    msg = nil
    start = Time.now
    loop do
      break if Time.now - start > 2

      begin
        msg = queue.pop(true)
        break if msg[1] == :stderr
      rescue ThreadError
        sleep 0.01
      end
    end

    assert_equal "error\n", msg[2], "stderr message should contain line content"
  end

  def test_streaming_command_sends_complete_message
    queue = Queue.new
    cmd = RatatuiRuby::Tea::Command.system("true", :output, stream: true)

    RatatuiRuby::Tea::Runtime.__send__(:dispatch, cmd, queue)

    messages = []
    start = Time.now
    loop do
      break if Time.now - start > 2

      begin
        msg = queue.pop(true)
        messages << msg
        break if msg[1] == :complete
      rescue ThreadError
        sleep 0.01
      end
    end

    complete_msgs = messages.select { |m| m[1] == :complete }
    assert_equal 1, complete_msgs.size, "Expected one :complete message"
  end

  def test_streaming_complete_message_has_correct_tag
    queue = Queue.new
    cmd = RatatuiRuby::Tea::Command.system("true", :my_tag, stream: true)

    RatatuiRuby::Tea::Runtime.__send__(:dispatch, cmd, queue)

    msg = nil
    start = Time.now
    loop do
      break if Time.now - start > 2

      begin
        msg = queue.pop(true)
        break if msg[1] == :complete
      rescue ThreadError
        sleep 0.01
      end
    end

    assert_equal :my_tag, msg[0], "Tag should match the command's tag"
  end

  def test_streaming_complete_message_has_exit_status
    queue = Queue.new
    cmd = RatatuiRuby::Tea::Command.system("exit 42", :output, stream: true)

    RatatuiRuby::Tea::Runtime.__send__(:dispatch, cmd, queue)

    msg = nil
    start = Time.now
    loop do
      break if Time.now - start > 2

      begin
        msg = queue.pop(true)
        break if msg[1] == :complete
      rescue ThreadError
        sleep 0.01
      end
    end

    assert_equal 42, msg[2][:status], "Exit status should be 42"
  end

  # Regression test: batch mode still works (stream: false default)
  def test_batch_mode_still_returns_single_message
    queue = Queue.new
    cmd = RatatuiRuby::Tea::Command.system("echo hello", :output)

    RatatuiRuby::Tea::Runtime.__send__(:dispatch, cmd, queue)

    msg = nil
    start = Time.now
    loop do
      break if Time.now - start > 2

      begin
        msg = queue.pop(true)
        break
      rescue ThreadError
        sleep 0.01
      end
    end

    # Batch mode: single message with hash containing stdout/stderr/status
    assert_equal :output, msg[0], "Tag should match"
    assert_kind_of Hash, msg[1], "Batch mode should return hash, not :stdout/:stderr symbol"
    assert msg[1].key?(:stdout), "Hash should have :stdout key"
    assert msg[1].key?(:stderr), "Hash should have :stderr key"
    assert msg[1].key?(:status), "Hash should have :status key"
  end

  # Error handling: invalid command sends :error message
  def test_streaming_invalid_command_sends_error_message
    queue = Queue.new
    cmd = RatatuiRuby::Tea::Command.system("nonexistent_cmd_xyz_123", :output, stream: true)

    RatatuiRuby::Tea::Runtime.__send__(:dispatch, cmd, queue)

    messages = []
    start = Time.now
    loop do
      break if Time.now - start > 2

      begin
        msg = queue.pop(true)
        messages << msg
        break if msg[1] == :complete || msg[1] == :error
      rescue ThreadError
        sleep 0.01
      end
    end

    # Should receive either :error message OR :complete with non-zero status
    error_or_complete = messages.find { |m| m[1] == :error || m[1] == :complete }
    assert error_or_complete, "Should receive :error or :complete message"
  end
end

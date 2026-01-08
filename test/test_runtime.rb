# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"
require "ratatui_ruby/test_helper"

class TestRuntime < Minitest::Test
  include RatatuiRuby::TestHelper

  private def ractor_error_pattern
    /ractor|frozen|shareable/i
  end

  def test_runtime_class_exists
    assert_kind_of Class, RatatuiRuby::Tea::Runtime
  end

  def test_runtime_responds_to_run
    assert_respond_to RatatuiRuby::Tea::Runtime, :run
  end

  def test_view_receives_model_and_tui
    model = { text: "hello" }.freeze
    view_args = nil

    view = -> (m, t) { view_args = [m, t]; t.clear }
    update = -> (msg, _m) { [model, RatatuiRuby::Tea::Cmd.quit] }

    with_test_terminal do
      RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
    end

    assert_equal model, view_args[0], "view should receive model as first arg"
    assert_kind_of RatatuiRuby::TUI, view_args[1], "view should receive TUI as second arg"
  end

  def test_update_can_return_plain_model
    model = { count: 0 }.freeze
    call_count = 0

    view = -> (_m, tui) { tui.clear }
    update = -> (msg, m) do
      call_count += 1
      if call_count >= 2 || msg.q?
        [m, RatatuiRuby::Tea::Cmd.quit]
      else
        m # Return plain model, no tuple
      end
    end

    with_test_terminal do
      inject_key("a") # First event: causes plain model return
      inject_key("q") # Second event: causes quit
      RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
    end

    assert_equal 2, call_count, "update should be called twice (once per event)"
  end

  def test_update_detects_array_model_vs_tuple
    # Model is a 2-element array - should not be confused with [model, cmd] tuple
    model = [:item1, :item2].freeze
    received_model = nil

    view = -> (m, tui) { received_model = m; tui.clear }
    update = -> (msg, m) do
      if msg.q?
        [m, RatatuiRuby::Tea::Cmd.quit]
      else
        m # Return the array model directly
      end
    end

    with_test_terminal do
      inject_key("a") # First event: returns array model
      inject_key("q") # Second event: quits
      RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
    end

    # The model should still be the 2-element array, not destructured
    assert_equal [:item1, :item2], received_model, "array model should not be confused with [model, cmd] tuple"
  end

  def test_update_can_return_cmd_only
    model = { count: 0 }.freeze
    received_model = nil

    view = -> (m, tui) { received_model = m; tui.clear }
    update = -> (_msg, _m) { RatatuiRuby::Tea::Cmd.quit }

    with_test_terminal do
      inject_key("a")
      RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
    end

    assert_same model, received_model, "model should be preserved when update returns Cmd only"
  end

  def test_update_can_return_nil
    model = { count: 0 }.freeze
    received_model = nil
    call_count = 0

    view = -> (m, tui) { received_model = m; tui.clear }
    update = -> (_msg, _m) do
      call_count += 1
      (call_count >= 2) ? RatatuiRuby::Tea::Cmd.quit : nil
    end

    with_test_terminal do
      inject_key("a")
      inject_key("b")
      RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
    end

    assert_same model, received_model, "model should be preserved when update returns nil"
  end

  def test_view_returning_nil_raises_error
    model = { text: "hello" }.freeze

    view = -> (_m, _t) { nil }
    update = -> (_msg, _m) { RatatuiRuby::Tea::Cmd.quit }

    error = assert_raises(RatatuiRuby::Error::Invariant) do
      with_test_terminal do
        inject_key("q")
        RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
      end
    end

    assert_match(/\bnil\b/i, error.message, "error message should mention 'nil'")
  end

  def test_view_returning_clear_renders_empty_screen
    model = { text: "hello" }.freeze
    view_called = false

    view = -> (_m, tui) { view_called = true; tui.clear }
    update = -> (_msg, _m) { RatatuiRuby::Tea::Cmd.quit }

    # tui.clear is the intentional way to render nothing
    with_test_terminal do
      inject_key("q")
      RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
    end

    assert view_called, "view should have been called"
  end

  def test_mutable_model_raises_error
    mutable_model = { count: 0 } # NOT frozen

    view = -> (_m, tui) { tui.clear }
    update = -> (_msg, _m) { RatatuiRuby::Tea::Cmd.quit }

    error = assert_raises(RatatuiRuby::Error::Invariant) do
      with_test_terminal do
        inject_key("q")
        RatatuiRuby::Tea::Runtime.run(model: mutable_model, view:, update:)
      end
    end

    assert_match ractor_error_pattern, error.message
  end

  def test_update_returning_mutable_model_raises_error
    model = { count: 0 }.freeze

    view = -> (_m, tui) { tui.clear }
    update = -> (_msg, _m) { { count: 1 } } # Returns mutable hash - NOT frozen

    error = assert_raises(RatatuiRuby::Error::Invariant) do
      with_test_terminal do
        inject_key("a")
        inject_key("q")
        RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
      end
    end

    assert_match ractor_error_pattern, error.message
  end

  def test_update_returning_frozen_model_succeeds
    model = { count: 0 }.freeze
    final_model = nil

    view = -> (m, tui) { final_model = m; tui.clear }
    update = -> (msg, m) do
      msg.q? ? [m, RatatuiRuby::Tea::Cmd.quit] : { count: m[:count] + 1 }.freeze
    end

    with_test_terminal do
      inject_key("a") # Triggers update that returns frozen model
      inject_key("q")
      RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
    end

    assert_equal({ count: 1 }, final_model)
  end

  def test_init_triggers_update_before_first_event
    model = { initialized: false }.freeze
    init_ran = false

    view = -> (_m, tui) { tui.clear }
    update = -> (msg, m) do
      case msg
      when :init_complete
        init_ran = true
        [{ initialized: true }.freeze, nil]
      else
        [m, RatatuiRuby::Tea::Cmd.quit]
      end
    end

    # init: is a Cmd that returns a message
    init_cmd = -> { :init_complete }

    with_test_terminal do
      inject_key("q")
      RatatuiRuby::Tea::Runtime.run(model:, view:, update:, init: init_cmd)
    end

    assert init_ran, "init command should trigger update with :init_complete message"
  end

  def test_runtime_executes_cmd_exec
    model = { output: nil }.freeze
    received_stdout = nil

    view = -> (_m, tui) { tui.clear }
    update = -> (msg, m) do
      case msg
      in [:got_output, { stdout:, status: 0 }]
        received_stdout = stdout.strip
        [Ractor.make_shareable({ output: stdout }), RatatuiRuby::Tea::Cmd.quit]
      else
        # First event triggers the exec command
        [m, RatatuiRuby::Tea::Cmd.exec("echo hello", :got_output)]
      end
    end

    # Stub Open3.capture3 to avoid actual shell execution
    require "open3"
    mock_status = Object.new
    mock_status.define_singleton_method(:exitstatus) { 0 }
    Open3.stub(:capture3, ["hello\n", "", mock_status]) do
      with_test_terminal do
        inject_key("a") # triggers exec
        RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
      end
    end

    assert_equal "hello", received_stdout
  end

  def test_runtime_executes_cmd_exec_failure
    model = { error: nil }.freeze
    received_stderr = nil

    view = -> (_m, tui) { tui.clear }
    update = -> (msg, m) do
      case msg
      in [:ran_cmd, { stderr:, status: }] if status != 0
        received_stderr = stderr
        [Ractor.make_shareable({ error: stderr }), RatatuiRuby::Tea::Cmd.quit]
      else
        [m, RatatuiRuby::Tea::Cmd.exec("false", :ran_cmd)]
      end
    end

    # Stub Open3.capture3 for failure
    require "open3"
    mock_status = Object.new
    mock_status.define_singleton_method(:exitstatus) { 1 }
    Open3.stub(:capture3, ["", "command failed\n", mock_status]) do
      with_test_terminal do
        inject_key("a")
        RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
      end
    end

    assert_equal "command failed\n", received_stderr
  end

  def test_runtime_executes_cmd_exec_success_with_stderr_noise
    # Some programs write output to stdout AND noise/warnings to stderr on success
    model = { output: nil, noise: nil }.freeze
    received_stdout = nil
    received_stderr = nil

    view = -> (_m, tui) { tui.clear }
    update = -> (msg, m) do
      case msg
      in [:ran_cmd, { stdout:, stderr:, status: 0 }]
        received_stdout = stdout
        received_stderr = stderr
        [Ractor.make_shareable({ output: stdout, noise: stderr }), RatatuiRuby::Tea::Cmd.quit]
      else
        [m, RatatuiRuby::Tea::Cmd.exec("compiler --verbose", :ran_cmd)]
      end
    end

    require "open3"
    mock_status = Object.new
    mock_status.define_singleton_method(:exitstatus) { 0 }
    Open3.stub(:capture3, ["compiled.o\n", "warning: deprecated syntax\n", mock_status]) do
      with_test_terminal do
        inject_key("a")
        RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
      end
    end

    assert_equal "compiled.o\n", received_stdout
    assert_equal "warning: deprecated syntax\n", received_stderr
  end
end

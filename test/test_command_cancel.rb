# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"

class TestCommandCancel < Minitest::Test
  def test_cancel_returns_cancel_instance
    handle = Object.new.freeze

    result = RatatuiRuby::Tea::Command.cancel(handle)

    assert_kind_of RatatuiRuby::Tea::Command::Cancel, result
  end

  def test_cancel_handle_returns_original
    handle = Object.new.freeze

    result = RatatuiRuby::Tea::Command.cancel(handle)

    assert_same handle, result.handle
  end

  def test_cancel_is_ractor_shareable
    handle = Object.new.freeze

    result = RatatuiRuby::Tea::Command.cancel(handle)

    assert Ractor.shareable?(result), "Command::Cancel should be Ractor-shareable"
  end
end

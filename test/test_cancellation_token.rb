# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"

class TestCancellationToken < Minitest::Test
  def test_cancellation_token_starts_not_cancelled
    token = RatatuiRuby::Tea::Command::CancellationToken.new
    refute token.cancelled?, "Fresh token should not be cancelled"
  end

  def test_cancellation_token_cancelled_after_cancel!
    token = RatatuiRuby::Tea::Command::CancellationToken.new
    token.cancel!
    assert token.cancelled?, "Token should be cancelled after cancel!"
  end

  def test_cancellation_token_counts_all_cancel_calls_concurrently
    token = RatatuiRuby::Tea::Command::CancellationToken.new
    thread_count = 10
    calls_per_thread = 10

    threads = thread_count.times.map do
      Thread.new do
        calls_per_thread.times { token.cancel! }
      end
    end

    threads.each(&:join)

    expected = thread_count * calls_per_thread
    assert_equal expected, token.cancel_count,
      "All cancel! calls should be counted (got #{token.cancel_count}, expected #{expected})"
  end

  def test_none_is_never_cancelled
    refute RatatuiRuby::Tea::Command::CancellationToken::NONE.cancelled?,
      "NONE should never be cancelled"
  end

  def test_none_cancel_is_noop
    # Should not raise
    RatatuiRuby::Tea::Command::CancellationToken::NONE.cancel!
  end

  def test_none_is_ractor_shareable
    assert Ractor.shareable?(RatatuiRuby::Tea::Command::CancellationToken::NONE),
      "NONE should be Ractor-shareable"
  end
end

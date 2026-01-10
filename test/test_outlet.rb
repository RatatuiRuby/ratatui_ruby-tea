# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"
require "ratatui_ruby/test_helper"

class TestOutlet < Minitest::Test
  include RatatuiRuby::TestHelper
  def test_put_pushes_message_to_queue
    queue = Queue.new
    outlet = RatatuiRuby::Tea::Command::Outlet.new(queue)

    outlet.put(:hello, :world)

    assert_equal [:hello, :world], queue.pop
  end

  def test_put_raises_in_debug_mode_for_non_shareable_payload
    queue = Queue.new
    outlet = RatatuiRuby::Tea::Command::Outlet.new(queue)
    mutable_hash = { data: "not frozen" } # NOT Ractor-shareable

    error = assert_raises(RatatuiRuby::Error::Invariant) do
      outlet.put(:bad, mutable_hash)
    end

    assert_match(/ractor|shareable/i, error.message)
  end

  def test_put_allows_non_shareable_in_production_mode
    queue = Queue.new
    outlet = RatatuiRuby::Tea::Command::Outlet.new(queue)
    mutable_hash = { data: "not frozen" }

    RatatuiRuby::Debug.suppress_debug_mode do
      outlet.put(:ok, mutable_hash) # Should NOT raise
    end

    assert_equal [:ok, mutable_hash], queue.pop
  end
end

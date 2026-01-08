# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "base"

# UPDATE using the declarative Tea::Router DSL.
#
# This is the minimal-boilerplate approach: declare routes and keymaps,
# let from_router generate the UPDATE lambda. Maximum DX, least control.
module DashboardRouter
  include RatatuiRuby::Tea::Router

  Command = RatatuiRuby::Tea::Command

  # Shared with other UPDATE variants
  Model = DashboardBase::Model
  INITIAL = DashboardBase::INITIAL
  VIEW = DashboardBase::VIEW

  route :stats, to: StatsPanel
  route :network, to: NetworkPanel

  keymap do
    key "q", -> { Command.exit }
    key :ctrl_c, -> { Command.exit }
    key "s", -> { SystemInfo.fetch_command }, route: :stats
    key "d", -> { DiskUsage.fetch_command }, route: :stats
    key "p", -> { Ping.fetch_command }, route: :network
    key "u", -> { Uptime.fetch_command }, route: :network
  end

  UPDATE = from_router
end

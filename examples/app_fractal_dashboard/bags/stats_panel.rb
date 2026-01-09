# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "system_info"
require_relative "disk_usage"

# Composes SystemInfo and DiskUsage in a horizontal layout.
module StatsPanel
  Model = Data.define(:system_info, :disk_usage)

  INITIAL = Model.new(
    system_info: SystemInfo::INITIAL,
    disk_usage: DiskUsage::INITIAL
  )

  VIEW = lambda do |model, tui, disabled: false|
    tui.layout(
      direction: :horizontal,
      constraints: [tui.constraint_percentage(50), tui.constraint_percentage(50)],
      children: [
        SystemInfo::VIEW.call(model.system_info, tui, disabled:),
        DiskUsage::VIEW.call(model.disk_usage, tui, disabled:),
      ]
    )
  end

  UPDATE = lambda do |message, model|
    case message
    in [:system_info, *rest]
      child_message = [:system_info, *rest]
      new_child, command = SystemInfo::UPDATE.call(child_message, model.system_info)
      [model.with(system_info: new_child), command]
    in [:disk_usage, *rest]
      child_message = [:disk_usage, *rest]
      new_child, command = DiskUsage::UPDATE.call(child_message, model.disk_usage)
      [model.with(disk_usage: new_child), command]
    else
      [model, nil]
    end
  end
end

# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

# Streaming output bag for custom shell command modal.
#
# Displays interleaved stdout/stderr. Border color reflects exit status.
# Sets dismissed: in model for parent to detect.
module CustomShellOutput
  Chunk = Data.define(:stream, :text)
  Model = Data.define(:command, :chunks, :running, :exit_status, :dismissed)
  INITIAL = Ractor.make_shareable(Model.new(command: "", chunks: [].freeze, running: false, exit_status: nil, dismissed: false))

  VIEW = lambda do |model, tui|
    # Build styled spans from chunks
    spans = if model.chunks.empty? && model.running
      [tui.text_span(content: "Running...", style: tui.style(fg: :dark_gray))]
    else
      model.chunks.map do |chunk|
        style = (chunk.stream == :stderr) ? tui.style(fg: :yellow) : nil
        tui.text_span(content: chunk.text, style:)
      end
    end

    # Border color: green if exited 0, red if exited non-zero, default if running
    border_style = case model.exit_status
                   when nil then nil
                   when 0 then tui.style(fg: :green)
                   else tui.style(fg: :red)
    end

    left_title = model.running ? "ESC: Cancel" : "ESC: Dismiss"
    display_cmd = (model.command.length > 60) ? "#{model.command[0..57]}..." : model.command

    tui.center(
      width_percent: 80,
      height_percent: 80,
      child: tui.overlay(
        layers: [
          tui.clear,
          tui.block(
            title: display_cmd,
            titles: [
              { content: left_title, position: :bottom, alignment: :left },
              { content: "ENTER: Dismiss", position: :bottom, alignment: :right },
            ],
            borders: [:all],
            border_style:,
            children: [tui.paragraph(text: spans)]
          ),
        ]
      )
    )
  end

  UPDATE = lambda do |message, model|
    case message
    in [:stdout, chunk]
      new_chunks = Ractor.make_shareable([*model.chunks, Chunk.new(stream: :stdout, text: chunk)].freeze)
      [model.with(chunks: new_chunks), nil]

    in [:stderr, chunk]
      new_chunks = Ractor.make_shareable([*model.chunks, Chunk.new(stream: :stderr, text: chunk)].freeze)
      [model.with(chunks: new_chunks), nil]

    in [:complete, { status: }]
      [model.with(running: false, exit_status: status), nil]

    in [:error, { message: error_msg }]
      new_chunks = Ractor.make_shareable([*model.chunks, Chunk.new(stream: :stderr, text: "Error: #{error_msg}\n")].freeze)
      [model.with(chunks: new_chunks, running: false, exit_status: 1), nil]

    in _ if message.respond_to?(:esc?) && message.esc?
      [model.with(dismissed: true), nil]

    in _ if message.respond_to?(:enter?) && message.enter?
      [model.with(dismissed: true), nil]

    else
      [model, nil]
    end
  end
end

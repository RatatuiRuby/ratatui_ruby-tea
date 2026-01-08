<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Feature Priorities

This document outlines the critical next steps for `ratatui_ruby-tea`. Each item explains the context, the problem, and the solution, following our [Documentation Style](../ratatui_ruby/doc/contributors/documentation_style.md).

## 1. Composition (Cmd.map)

**Context:** Real applications grow. You start with a file picker. Then a modal. Then a sidebar. Each component has its own model and update function.

**Problem:** The Tea architecture naturally isolates components. A parent model holds a child model. But when the child update function returns a message (like `:selected`), the parent `update` function only understands its own messages. It cannot "hear" the child. The architecture breaks at the boundary of the first file.

**Solution:** Implement `Cmd.map(cmd) { |child_msg| ... }`. This wraps the child's effect. When the effect completes, the runtime passes the result through the block, transforming the child's message into a parent's message. This restores the flow of data up the tree.

## 2. Parallelism (Cmd.batch)

**Context:** Applications often need to do two things at once. You initialize the app. You need to load the config *and* fetch the latest data *and* start the tick timer.

**Problem:** The `update` function returns a single tuple `[Model, Cmd]`. It cannot return `[Model, Cmd1, Cmd2]`. Without a way to group them, you are forced to sequence independent operations, making the UI feel slow and linear.

**Solution:** Implement `Cmd.batch([cmd1, cmd2, ...])`. This command takes an array of commands and submits them all to the runtime. The runtime executes them in parallel (where possible) or concurrently.

## 3. Serial Execution (Cmd.sequence)

**Context:** Some effects depend on others. You cannot read a file until you have downloaded it. You cannot query the database until you have opened the connection.

**Problem:** The Tea architecture relies on async messages. You send a command, and *eventually* you get a message. To chain actions, you must handle the first success message in `update`, then return the second command. This smears a single logical transaction across multiple independent `case` clauses, creating "callback hell" but in the shape of a state machine.

**Solution:** Implement `Cmd.sequence([cmd1, cmd2, ...])`. This command executes the first command. If successful, it runs the next. If any fail, it stops. Note: This assumes commands have a standard "success/failure" result shape, or simply runs them blindly. (Design decision required: does `sequence` wait for the message, or just the execution?)

## 4. Time (Cmd.tick)

**Context:** Animations and real-time updates. A spinner rotating. A clock ticking. Evaluation metrics updating live.

**Problem:** The runtime blocks on input. If the user doesn't type or click, the screen stays frozen. You cannot implement a simple "Loading..." spinner because the frame never updates.

**Solution:** Implement `Cmd.tick(interval, tag)`. This command sleeps for the interval and then sends a message. The `update` function handles the message and returns the *same* tick command again. This creates a recursive loop, driving the frame rate independent of user input.

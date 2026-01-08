<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Application Testing Guide

This guide explains how to test your RatatuiRuby applications using the provided `RatatuiRuby::TestHelper`.

## Overview

You need to verify that your application looks and behaves correctly. Manually checking every character on a terminal screen is tedious. Dealing with race conditions and complex state management in tests creates friction.

The `TestHelper` module solves this. It provides a headless "test terminal" to capture output and a suite of robust assertions to verify state.

Use it to write fast, deterministic tests for your TUI applications.

## Setup

First, require the test helper in your test file or `test_helper.rb`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
require "ratatui_ruby/test_helper"
require "minitest/autorun" # or your preferred test framework
```
<!-- SPDX-SnippetEnd -->

Then, include the module in your test class:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
class MyApplicationTest < Minitest::Test
  include RatatuiRuby::TestHelper
  # ...
end
```
<!-- SPDX-SnippetEnd -->

## Writing Tests

_Because this gem is in pre-release, it lacks documentation. Please check the source files and automated tests._

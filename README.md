<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# ratatui_ruby-tea

[![
builds.sr.ht status](https://builds.sr.ht/~kerrick/ratatui_ruby-tea.svg)](https://builds.sr.ht/~kerrick/ratatui_ruby-tea?) [![
License](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fgit.sr.ht%2F~kerrick%2Fratatui_ruby-tea%2Fblob%2Fstable%2Fratatui_ruby-tea.gemspec&search=spec%5C.license%20%3D%20%22(.*)%22&replace=%241&label=License&color=a2c93e)](https://spdx.org/licenses/LGPL-3.0-or-later.html) [![
Gem Total Downloads](https://img.shields.io/gem/dt/ratatui_ruby-tea)](https://rubygems.org/gems/ratatui_ruby-tea) [![
Gem Version](https://img.shields.io/gem/v/ratatui_ruby-tea)](https://rubygems.org/gems/ratatui_ruby-tea) [![
Mailing List: Discussion](https://img.shields.io/badge/mailing_list-discussion-5865F2.svg?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IiNmZmZmZmYiIHN0cm9rZS13aWR0aD0iMiIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIiBjbGFzcz0iaWNvbiBpY29uLXRhYmxlciBpY29ucy10YWJsZXItb3V0bGluZSBpY29uLXRhYmxlci1tYWlsIj48cGF0aCBzdHJva2U9Im5vbmUiIGQ9Ik0wIDBoMjR2MjRIMHoiIGZpbGw9Im5vbmUiLz48cGF0aCBkPSJNMyA3YTIgMiAwIDAgMSAyIC0yaDE0YTIgMiAwIDAgMSAyIDJ2MTBhMiAyIDAgMCAxIC0yIDJoLTE0YTIgMiAwIDAgMSAtMiAtMnYtMTB6IiAvPjxwYXRoIGQ9Ik0zIDdsOSA2bDkgLTYiIC8+PC9zdmc+Cg==)](https://lists.sr.ht/~kerrick/ratatui_ruby-discuss) [![
Mailing List: Development](https://img.shields.io/badge/mailing_list-development-4954d5.svg?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IiNmZmZmZmYiIHN0cm9rZS13aWR0aD0iMiIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIiBjbGFzcz0iaWNvbiBpY29uLXRhYmxlciBpY29ucy10YWJsZXItb3V0bGluZSBpY29uLXRhYmxlci1tYWlsIj48cGF0aCBzdHJva2U9Im5vbmUiIGQ9Ik0wIDBoMjR2MjRIMHoiIGZpbGw9Im5vbmUiLz48cGF0aCBkPSJNMyA3YTIgMiAwIDAgMSAyIC0yaDE0YTIgMiAwIDAgMSAyIDJ2MTBhMiAyIDAgMCAxIC0yIDJoLTE0YTIgMiAwIDAgMSAtMiAtMnYtMTB6IiAvPjxwYXRoIGQ9Ik0zIDdsOSA2bDkgLTYiIC8+PC9zdmc+Cg==)](https://lists.sr.ht/~kerrick/ratatui_ruby-devel) [![
Mailing List: Announcements](https://img.shields.io/badge/mailing_list-announcements-3b44ac.svg?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IiNmZmZmZmYiIHN0cm9rZS13aWR0aD0iMiIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIiBjbGFzcz0iaWNvbiBpY29uLXRhYmxlciBpY29ucy10YWJsZXItb3V0bGluZSBpY29uLXRhYmxlci1tYWlsIj48cGF0aCBzdHJva2U9Im5vbmUiIGQ9Ik0wIDBoMjR2MjRIMHoiIGZpbGw9Im5vbmUiLz48cGF0aCBkPSJNMyA3YTIgMiAwIDAgMSAyIC0yaDE0YTIgMiAwIDAgMSAyIDJ2MTBhMiAyIDAgMCAxIC0yIDJoLTE0YTIgMiAwIDAgMSAtMiAtMnYtMTB6IiAvPjxwYXRoIGQ9Ik0zIDdsOSA2bDkgLTYiIC8+PC9zdmc+Cg==)](https://lists.sr.ht/~kerrick/ratatui_ruby-announce)


## Introduction

**ratatui_ruby-tea** is a gem in the [RatatuiRuby ecosystem](https://sr.ht/~kerrick/ratatui_ruby/).
**ratatui_ruby** is a community wrapper that is not affiliated with [the Ratatui team](https://github.com/orgs/ratatui/people).

> [!WARNING]
> **ratatui_ruby-tea** is currently in **PRE-RELEASE**. The API will change rapidly, even between minor and patch versions.

**[Why RatatuiRuby?](https://man.sr.ht/~kerrick/ratatui_ruby/why.md)** — Native Rust performance, zero runtime overhead, and Ruby's expressiveness. [See how we compare](https://man.sr.ht/~kerrick/ratatui_ruby/why.md) to CharmRuby, raw Rust, and Go.

Please join the **announce** mailing list at https://lists.sr.ht/~kerrick/ratatui_ruby-announce to stay up-to-date on new releases and announcements. See the [`trunk` branch](https://git.sr.ht/~kerrick/ratatui_ruby-tea/tree/trunk) for pre-release updates.


## Compatibility

**ratatui_ruby-tea** is designed to run on [everything Ruby does](https://www.ruby-lang.org/en/documentation/installation/), including:

- GNU/Linux, macOS, Windows, OpenBSD, and FreeBSD; and
- x86_64 (AMD, Intel) and ARM (Apple Silicon, Raspberry Pi).

We support the latest minor version of every
[non-eol Ruby version](https://www.ruby-lang.org/en/downloads/branches/),
including Ruby 4.


## Installation

Add this line to your application's Gemfile:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
gem "ratatui_ruby-tea"
```
<!-- SPDX-SnippetEnd -->

And then execute:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```bash
bundle install
```
<!-- SPDX-SnippetEnd -->

Or install it yourself with:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```bash
gem install ratatui_ruby-tea
```
<!-- SPDX-SnippetEnd -->


## Usage

**ratatui_ruby-tea** uses the Model-View-Update (MVU) pattern. You provide an immutable model, a view function, and an update function.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
<!-- SYNC:START:examples/verify_readme_usage/app.rb:mvu -->
```ruby
Model = Data.define(:text)
MODEL = Model.new(text: "Hello, Ratatui! Press 'q' to quit.")

VIEW = -> (model, tui) do
  tui.paragraph(
    text: model.text,
    alignment: :center,
    block: tui.block(
      title: "My Ruby TUI App",
      borders: [:all],
      border_style: { fg: "cyan" }
    )
  )
end

UPDATE = -> (msg, model) do
  if msg.q? || msg.ctrl_c?
    RatatuiRuby::Tea::Command.exit
  else
    model
  end
end

def run
  RatatuiRuby::Tea.run(model: MODEL, view: VIEW, update: UPDATE)
end
```
<!-- SYNC:END -->
<!-- SPDX-SnippetEnd -->

![Hello Ratatui](./doc/images/verify_readme_usage.png)

For a full tutorial, see [the Quickstart](./doc/getting_started/quickstart.md). For an explanation of the application architecture, see [Application Architecture](./doc/concepts/application_architecture.md).


## Features

_Because this gem is in pre-release, it lacks documentation. Please check the source files.


## Documentation

| Resource | Description |
|----------|-------------|
| [Quickstart](./doc/getting_started/quickstart.md) | Get running in 5 minutes |
| [Application Architecture](./doc/concepts/application_architecture.md) | Patterns for scaling your app |
| [Guides](./doc/index.md) | Tutorials, examples, and more |
| API Reference | To generate full RDoc documentation, run `bundle exec rake rdoc` |
| [Wiki](https://man.sr.ht/~kerrick/ratatui_ruby) | Learn more about the RatatuiRuby ecosystem |


## Contributing

Bug reports and pull requests are welcome on [sourcehut](https://sourcehut.org) at https://sr.ht/~kerrick/ratatui_ruby/. This project is intended to be a safe, productive collaboration, and contributors are expected to adhere to the [Code of Conduct](https://man.sr.ht/~kerrick/ratatui_ruby/code_of_conduct.md).


Want to help develop **ratatui_ruby-tea**? Check out the [contribution guide on the wiki](https://man.sr.ht/~kerrick/ratatui_ruby/contributing.md).

**Note**: Active development happens on the `trunk` branch. Use `trunk` if you are a contributor or want the latest cutting-edge features. `stable` is for stable releases only.


## Copyright & License

**ratatui_ruby-tea** is copyright 2026, Kerrick Long.

The library is [LGPL-3.0-or-later](./LICENSES/LGPL-3.0-or-later.txt): you can use it in proprietary applications, but you must share changes you make to **ratatui_ruby-tea** itself. Documentation snippets and widget examples are [MIT-0](./LICENSES/MIT-0.txt): copy and use them without attribution.

Documentation is [CC-BY-SA-4.0](./LICENSES/CC-BY-SA-4.0.txt). Build tooling and full app examples are [LGPL-3.0-or-later](./LICENSES/LGPL-3.0-or-later.txt). See each file's SPDX comment for specifics.

Some parts of this program are copied from other sources under appropriate reuse licenses, and the copyright belongs to their respective owners. See the [REUSE Specification – Version 3.3](https://reuse.software/spec-3.3/) for details.

This program was created with significant assistance from multiple LLMs. The process was human-controlled through creative prompts, with human contributions to each commit. See commit footers for model attribution. [declare-ai.org](https://declare-ai.org/1.0.0/creative.html)
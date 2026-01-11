<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Custom Commands: Ractor-Ready Design Specification

> **Status**: Draft (Ractor-Compatible Variant)  
> **Decision**: Worker Ractor Architecture + Data Commands

This document adapts the unified custom commands design for true Ractor parallelism. Commands are pure Data dispatched to pre-registered Actors.

---

## Key Differences from unified-draft.md

| Aspect | Thread Design | Ractor Design |
|--------|---------------|---------------|
| Command execution | Thread.new in dispatch | Pre-registered Actors |
| Command types | Callables (procs, classes) | Shareable Objects (Data, Frozen Hash) |
| Cancellation | CancellationToken with Mutex | Ractor message `Command.cancel` |
| Outlet | Wraps Thread::Queue | Wraps Ractor port |

---

## Executive Summary

Custom commands enable developers to extend Tea with custom side effects. The Ractor-ready design provides:

1. **Data Commands** — Any Ractor-shareable object (Data, Frozen Hash)
2. **Actors** — App-defined execution units registered at boot
3. **Ractor Outlet** — Messaging via Ractor ports
4. **Message-Based Cancellation** — `Command.cancel` sentinel (like `Command.exit`) via a Ractor message, instead of tokens

---

## Core Abstractions

### Data Commands (Replaces Callable Commands)

Commands are pure data describing *what* to do, not *how* to do it. While `Data.define` is recommended, any **Ractor-shareable** object is valid.

```ruby
module MyApp::Commands
  # Simple fetch command
  FetchUser = Data.define(:user_id, :envelope)

  # Long-running with custom grace period
  PollDatabase = Data.define(:interval, :envelope) do
    def tea_cancellation_grace_period = Float::INFINITY
  end

  # Default grace period (2.0s) via module
  WebSocketConnect = Data.define(:url, :envelope) do
    def tea_cancellation_grace_period = 5.0
  end
end
```

All commands must:
1. Be **Ractor-shareable** (deeply frozen).
2. Respond to `#envelope` (Duck Typing) to allow routing responses back to the Update loop.
  - An envelope should be a **Ractor-shareable object** optimized for pattern matching in your `update` loop.
    - **Symbols** (`:user_fetched`): Best for simple, readable routing.
    - **Classes** (`MyApp::User`): Best for **Class-Based Routing** (aligns message ownership with domain classes).
    - **Tuples** (`[:fetched_user, 123]`): Best for correlating specific instances (e.g., Request ID).
    - **Avoid**: Anything that complicates your future pattern matching or predicates.

### Command::Cancel (Sentinel Type)

Cancellation is requested via a special command type:

```ruby
module RatatuiRuby::Tea::Command
  Cancel = Data.define(:handle)
  
  def self.cancel(handle)
    Cancel.new(handle:)
  end
end
```

- **In update**: `Command.cancel(model.active_cmd)` dispatches the cancel request
- **In runtime dispatch**: Pattern match on `Command::Cancel`, look up worker by handle
- **In actors**: Pattern match on `Command::Cancel` to break the loop

### Actors (Replaces Thread Dispatch, `Command.custom`)

Actors are thin Ractor wrappers that know how to handle specific command types:

```ruby
module MyApp::Actors
  # HTTP fetch worker
  API_USER = Tea::Actor.new do
    loop do
      cmd, reply_port = Tea::Actor.receive
      
      case cmd
      when Command::Cancel
        break  # Shutdown worker
      when Commands::FetchUser
        response = Net::HTTP.get(URI("https://api.example.com/users/#{cmd.user_id}"))
        user = JSON.parse(response)
        reply_port.send([cmd.envelope, :success, user: user])
      rescue => e
        reply_port.send([cmd.envelope, :error, message: e.message])
      end
    end
  end

  # WebSocket worker (long-running)
  WEBSOCKET = Tea::Actor.new do
    connections = {}
    
    loop do
      cmd, reply_port = Tea::Actor.receive
      
      case cmd
      when Command::Cancel
        connections.each_value(&:close)
        break
      when Commands::WebSocketConnect
        ws = WebSocket::Client.new(cmd.url)
        connections[cmd] = ws
        
        ws.on_message do |msg|
          reply_port.send([cmd.envelope, :message, data: msg])
        end
        
        ws.connect
        reply_port.send([cmd.envelope, :connected])
      when Commands::WebSocketDisconnect
        ws = connections.delete(cmd.handle)
        ws&.close
        reply_port.send([cmd.envelope, :closed])
      end
    end
  end
end
```

### Actor Registration

Actors are wired to commands at application boot using the `handle` DSL:

```ruby
RatatuiRuby::Tea.configure do |config|
  config.handle Commands::FetchUser, with: Actors::API_USER
  config.handle Commands::PollDatabase, with: Actors::DATABASE
  config.handle Commands::WebSocketConnect, with: Actors::WEBSOCKET
end
```

### Ractor Facade

Ractor's API is experimental, and may change in future versions of Ruby. To
shield application developers from potential instability while making it easy to
eliminate the facade if this Ractor API becomes the final version,
RatatuiRuby::Tea provides a simple Ractor facade:

```ruby
module RatatuiRuby
  module Tea
    class Actor
      def self.new(&block) # Behaves exactly like Ractor.new
        Ractor.new(&block)
      end

      def self.receive # Behaves exactly like Ractor.receive
        Ractor.receive
      end
      
      def self.yield(obj) # Behaves exactly like Ractor.yield
        Ractor.yield(obj)
      end
    end
  end
end
```

This facade is optional, but will be the primary API shown in documentation,
most tests, tutorials, and example application code. Using Ractor directly must
be supported and proven by automated tests.

### Ractor Outlet (Replaces Thread::Queue Outlet)

The Outlet wraps Ractor messaging:

```ruby
module RatatuiRuby::Tea::Command
  class Outlet
    def initialize(reply_port)
      @reply_port = reply_port
    end

    def put(envelope, *payload) # To Ractors, not to Thread Queues
      message = [envelope, *payload].freeze
      @reply_port.send(message)
    end
  end
end
```

### Message-Based Cancellation (Replaces CancellationToken)

Cancellation is a message to the worker, not a shared token:

```ruby
# Runtime sends Command.cancel to worker
def cancel_command(handle)
  entry = @active_commands[handle]
  return unless entry

  worker = entry[:worker]
  
  # Send cancel message
  worker.send([Command.cancel, nil])
  
  # Wait for grace period
  grace = handle.tea_cancellation_grace_period
  if grace.finite?
    deadline = Time.now + grace
    while entry[:alive] && Time.now < deadline
      sleep 0.05
    end
  end
  
  # Force-terminate if still alive (Ractor doesn't have kill, may need to respawn)
  @active_commands.delete(handle)
end
```

### Application-Level Cancellation

Since commands are Objects with identity, the command instance itself serves as
the "Handle" (replacing the need for a separate `CancellationToken`). To support
UI-triggered cancellation, store the command in your model and use
`Command.cancel(handle)` to issue a stop request.

```ruby
def update(msg, model)
  case msg
  in :start_download
    # 1. Create and store the command (the handle)
    cmd = Commands::Download.new(url: "...", envelope: :downloaded)
    [model.with(active_cmd: cmd), cmd]

  in :cancel_clicked
    return [model, nil] unless model.active_cmd

    # 2. Dispatch a cancel request targeting the specific command
    effect = Command.cancel(model.active_cmd)
    [model.with(active_cmd: nil), effect]
  end
end
```

---

## Runtime Integration

### Dispatch Logic

```ruby
class Runtime
  def initialize
    @reply_port = Ractor.new { loop { Ractor.receive } }  # Message collector
    @active_commands = {}  # handle => { worker:, alive: }
    @workers = {}  # command_class => worker_ractor
  end

  def register_worker(command_class, worker_ractor)
    @workers[command_class] = worker_ractor
  end

  private def dispatch(command)
    case command
    when Command::System
      dispatch_system(command)
    when Command::Mapped
      dispatch_mapped(command)
    when Command::Cancel
      cancel_command(command.handle)
    else
      dispatch_to_worker(command)
    end
  end

  private def dispatch_to_worker(command)
    worker = @workers[command.class]
    raise "No worker registered for #{command.class}" unless worker

    worker.send([command, @reply_port])
    @active_commands[command] = { worker: worker, alive: true }
  end
end
```

### Main Loop with Ractor.select

```ruby
def run
  loop do
    # Receive from either input events or command replies
    ractor, message = Ractor.select(@input_ractor, @reply_port)
    
    case ractor
    when @input_ractor
      handle_input(message)
    when @reply_port
      handle_command_message(message)
    end
  end
end
```

---

## Usage Examples

### Simple Fetch

```ruby
# Define command (Data)
module Commands
  FetchUser = Data.define(:user_id, :envelope)
end

# Define actor (Ractor)
module Actors
  API_USER = Ractor.new do
    loop do
      cmd, reply = Ractor.receive
      break if cmd.is_a?(Command::Cancel)
      
      user = API.fetch_user(cmd.user_id)
      reply.send([cmd.envelope, :success, user: user])
    end
  end
end

# Register
Tea.configure do |config|
  config.handle Commands::FetchUser, with: Actors::API_USER
end
# In update
def update(message, model)
  case message
  in :load_self
    [model, Commands::FetchUser.new(user_id: 123, envelope: :self_loaded)]
  in [:self_loaded, :success, user:]
    [model.with(user: user), nil]
  in :load_friend
    [model, Commands::FetchUser.new(user_id: 456, envelope: :friend_loaded)]
  in [:friend_loaded, :success, user:]
    [model.with(friend: user), nil]
  end
end
```

### Long-Running with Cancellation (Sidecar Thread Pattern)

Ruby's `Ractor.receive` blocks, so long-running actors need a **Sidecar Thread** to listen for cancel messages while the main thread works.

Threads within a Ractor share memory (unlike Ractors which are isolated), so a simple boolean flag coordinates between the listener and worker threads.

> [!NOTE]
> This does **not** violate Ractor safety. The shared `keep_running` flag never leaves the actor's Ractor—only messages crossing Ractor boundaries must be shareable. App developers still write shareable models and messages; the Sidecar Thread is a hidden framework concern.

```ruby
module Commands
  DatabasePoller = Data.define(:interval, :envelope) do
    def tea_cancellation_grace_period = Float::INFINITY
  end
end

module Actors
  DATABASE = Ractor.new do
    loop do
      # Receive the command (blocks until dispatched)
      cmd, reply = Ractor.receive
      break if cmd.is_a?(Command::Cancel)

      # 1. Shared flag between threads (within this Ractor)
      keep_running = true

      # 2. Sidecar thread listens for cancel messages
      listener = Thread.new do
        loop do
          msg, _ = Ractor.receive
          if msg.is_a?(Command::Cancel)
            keep_running = false
            break
          end
        end
      end

      # 3. Main thread does the work, checking the flag
      while keep_running
        records = DB.poll
        reply.send([cmd.envelope, :batch, records: records])
        sleep cmd.interval
      end

      # Cleanup
      listener.join
      reply.send([cmd.envelope, :stopped])
    end
  end
end
```

**Why this works:**
- `Ractor.receive` blocks the *listener thread*, not the main thread
- Checking `keep_running` is O(1), non-blocking
- The main thread stays responsive to its work loop

---

## Comparison with Thread Design

| Aspect | Thread (unified-draft) | Ractor (this spec) |
|--------|------------------------|---------------------|
| Parallelism | GVL-limited | True parallel |
| Command form | Callable (proc/class) | Ractor-shareable Object |
| Execution | Thread.new per command | Pre-registered Actors |
| Cancellation | Shared CancellationToken | Message to Actor (`Command.cancel`) |
| Complexity | Simpler | More upfront setup |
| Flexibility | Any callable | Registered types only |

---

## Migration Path

### From Thread Design

1. Convert command classes to `Data.define`
2. Extract `call` logic into Actors
3. Wire up Actors at boot
4. Replace `CancellationToken.cancelled?` checks with message handling

### Gradual Adoption

The runtime can support both:
- Built-in commands (System, Exit) use Ractors
- Custom commands use Threads initially, migrate to Ractors

---

## Open Questions

1. ~~**Non-blocking Ractor.receive**~~: Resolved. Use **Sidecar Thread** pattern—spawn a thread inside the Ractor to block on `receive` while the main thread works.
2. **Worker lifecycle**: Respawn workers after force-termination?
3. **Error propagation**: Worker errors → reply_port standardization?
4. **Multiple commands per worker**: Queue or spawn per-command?

---

## RBS Type Definitions

```rbs
module RatatuiRuby::Tea::Command
  class Outlet
    def initialize: (Ractor reply_port) -> void
    def put: (Symbol envelope, *untyped payload) -> void
  end

  interface _DataCommand
    def envelope: () -> Symbol
    def tea_cancellation_grace_period: () -> Float
  end
end

class RatatuiRuby::Tea::Runtime
  def handle: (Class command_class, with: Ractor actor) -> void
end
```

---

## Pattern Lineage

| Component | Pattern | Source |
|-----------|---------|--------|
| Data Commands | **Value Object** | Domain-Driven Design |
| Worker Ractor | **Actor** | Hewitt Actor Model |
| Reply Port | **Request-Reply** | Enterprise Integration Patterns |
| Worker Registration | **Service Locator** | Patterns of Enterprise Architecture |

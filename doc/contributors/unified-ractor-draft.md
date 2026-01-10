<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Custom Commands: Ractor-Ready Design Specification

> **Status**: Draft (Ractor-Compatible Variant)  
> **Decision**: Worker Ractor Architecture + Data Commands

This document adapts the unified custom commands design for true Ractor parallelism. Commands are pure Data dispatched to pre-registered Worker Ractors.

---

## Key Differences from unified-draft.md

| Aspect | Thread Design | Ractor Design |
|--------|---------------|---------------|
| Command execution | Thread.new in dispatch | Pre-registered Worker Ractors |
| Command types | Callables (procs, classes) | Pure Data.define |
| Cancellation | CancellationToken with Mutex | Ractor message `:cancel` |
| Outlet | Wraps Thread::Queue | Wraps Ractor port |

---

## Executive Summary

Custom commands enable developers to extend Tea with custom side effects. The Ractor-ready design provides:

1. **Data Commands** — Pure `Data.define` types (Ractor-shareable)
2. **Worker Ractors** — App-defined execution units registered at boot
3. **Ractor Outlet** — Messaging via Ractor ports
4. **Message-Based Cancellation** — `:cancel` messages instead of tokens

---

## Core Abstractions

### Data Commands (Replaces Callable Commands)

Commands are pure data describing *what* to do, not *how* to do it:

```ruby
module MyApp::Commands
  # Simple fetch command
  FetchUser = Data.define(:user_id, :tag)

  # Long-running with custom grace period
  PollDatabase = Data.define(:interval, :tag) do
    def tea_cancellation_grace_period = Float::INFINITY
  end

  # Default grace period (2.0s) via module
  WebSocketConnect = Data.define(:url, :tag) do
    def tea_cancellation_grace_period = 5.0
  end
end
```

All commands must:
1. Be `Data.define` (frozen, Ractor-shareable)
2. Include a `:tag` field for routing messages back

### Worker Ractors (Replaces Thread Dispatch)

Workers are Ractor loops that know how to execute command types:

```ruby
module MyApp::Workers
  # HTTP fetch worker
  FETCH = Ractor.new do
    loop do
      cmd, reply_port = Ractor.receive
      
      case cmd
      when :cancel
        break  # Shutdown worker
      when Commands::FetchUser
        response = Net::HTTP.get(URI("https://api.example.com/users/#{cmd.user_id}"))
        user = JSON.parse(response)
        reply_port.send([cmd.tag, :success, user: user])
      rescue => e
        reply_port.send([cmd.tag, :error, message: e.message])
      end
    end
  end

  # WebSocket worker (long-running)
  WEBSOCKET = Ractor.new do
    connections = {}
    
    loop do
      cmd, reply_port = Ractor.receive
      
      case cmd
      when :cancel
        connections.each_value(&:close)
        break
      when Commands::WebSocketConnect
        ws = WebSocket::Client.new(cmd.url)
        connections[cmd] = ws
        
        ws.on_message do |msg|
          reply_port.send([cmd.tag, :message, data: msg])
        end
        
        ws.connect
        reply_port.send([cmd.tag, :connected])
      when Commands::WebSocketDisconnect
        ws = connections.delete(cmd.handle)
        ws&.close
        reply_port.send([cmd.tag, :closed])
      end
    end
  end
end
```

### Worker Registration

Workers register at application boot:

```ruby
RatatuiRuby::Tea.configure do |config|
  config.register_worker Commands::FetchUser, Workers::FETCH
  config.register_worker Commands::PollDatabase, Workers::DATABASE
  config.register_worker Commands::WebSocketConnect, Workers::WEBSOCKET
end
```

### Ractor Outlet (Replaces Thread::Queue Outlet)

The Outlet wraps Ractor messaging:

```ruby
module RatatuiRuby::Tea::Command
  class RactorOutlet
    def initialize(reply_port)
      @reply_port = reply_port
    end

    def put(tag, *payload)
      message = [tag, *payload].freeze
      @reply_port.send(message)
    end
  end
end
```

### Message-Based Cancellation (Replaces CancellationToken)

Cancellation is a message to the worker, not a shared token:

```ruby
# Runtime sends :cancel to worker
def cancel_command(handle)
  entry = @active_commands[handle]
  return unless entry

  worker = entry[:worker]
  
  # Send cancel message
  worker.send([:cancel, nil])
  
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
  FetchUser = Data.define(:user_id, :tag)
end

# Define worker (Ractor)
module Workers
  FETCH = Ractor.new do
    loop do
      cmd, reply = Ractor.receive
      break if cmd == :cancel
      
      user = API.fetch_user(cmd.user_id)
      reply.send([cmd.tag, :success, user: user])
    end
  end
end

# Register
Tea.register_worker Commands::FetchUser, Workers::FETCH

# In update
def update(msg, model)
  case msg
  in :load_user
    [model, Commands::FetchUser.new(user_id: 123, tag: :user_loaded)]
  in [:user_loaded, :success, user:]
    [model.with(user: user), nil]
  end
end
```

### Long-Running with Cancellation

```ruby
module Commands
  DatabasePoller = Data.define(:interval, :tag) do
    def tea_cancellation_grace_period = Float::INFINITY
  end
end

module Workers
  DATABASE = Ractor.new do
    running = true
    
    loop do
      # Non-blocking check for cancel
      cmd, reply = Ractor.receive
      
      if cmd == :cancel
        running = false
        break
      end
      
      # Poll loop
      while running
        records = DB.poll
        reply.send([cmd.tag, :batch, records: records])
        sleep cmd.interval
        
        # Check for cancel between iterations
        # (Would need non-blocking receive pattern)
      end
    end
  end
end
```

---

## Comparison with Thread Design

| Aspect | Thread (unified-draft) | Ractor (this spec) |
|--------|------------------------|---------------------|
| Parallelism | GVL-limited | True parallel |
| Command form | Callable (proc/class) | Data.define |
| Execution | Thread.new per command | Pre-registered workers |
| Cancellation | Shared CancellationToken | Message to worker |
| Complexity | Simpler | More upfront setup |
| Flexibility | Any callable | Registered types only |

---

## Migration Path

### From Thread Design

1. Convert command classes to `Data.define`
2. Extract `call` logic into Worker Ractors
3. Register workers at boot
4. Replace `CancellationToken.cancelled?` checks with message handling

### Gradual Adoption

The runtime can support both:
- Built-in commands (System, Exit) use Ractors
- Custom commands use Threads initially, migrate to Ractors

---

## Open Questions

1. **Non-blocking Ractor.receive**: How to check for cancel messages during long loops?
2. **Worker lifecycle**: Respawn workers after force-termination?
3. **Error propagation**: Worker errors → reply_port standardization?
4. **Multiple commands per worker**: Queue or spawn per-command?

---

## RBS Type Definitions

```rbs
module RatatuiRuby::Tea::Command
  class RactorOutlet
    def initialize: (Ractor reply_port) -> void
    def put: (Symbol tag, *untyped payload) -> void
  end

  interface _DataCommand
    def tag: () -> Symbol
    def tea_cancellation_grace_period: () -> Float
  end
end

class RatatuiRuby::Tea::Runtime
  def register_worker: (Class command_class, Ractor worker) -> void
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

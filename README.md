# Crossroad

A high-performance Phoenix chat application using Discord's Manifold architecture for efficient distributed message broadcasting.

Manifold reduces network overhead by grouping subscriber PIDs by Erlang node before sending. Instead of N `send/2` calls for N subscribers, it sends 1 message per node—reducing packets by up to 50% at Discord's scale.

## Architecture

```
Client → WebSocket → ChatChannel → PubSub → Router → Partitioners → Workers → PIDs
```

- **Router:** Groups PIDs by node, routes to remote partitioners
- **Partitioner:** Consistently hashes PIDs, distributes to workers  
- **Worker:** Final `send/2` delivery with hibernation
- **Registry:** ETS-backed room-to-PID mapping
- **Presence:** CRDT-based online status tracking

## Quick Start

```bash
mix setup          # Install dependencies
mix phx.server     # Start server
# Or: iex -S mix phx.server

# Connect via WebSocket to ws://localhost:4000/socket
# Join channel: "chat:lobby"
```

## Usage

```elixir
# Subscribe to a room
Crossroad.PubSub.subscribe("chat:lobby", self())

# Broadcast a message
Crossroad.PubSub.broadcast("chat:lobby", %{user: "alice", text: "Hello!"})

# With options for large messages
Crossroad.PubSub.broadcast("chat:lobby", large_msg, pack_mode: :binary)
```

## Configuration

```elixir
# config/runtime.exs
config :crossroad, :manifold,
  partitioners: 8,                    # Max 32
  workers_per_partitioner: 8,         # Per CPU core
  senders: 64,                        # For offload mode
  hibernate_delay: 60_000             # Memory optimization
```
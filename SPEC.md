# CloudMsg - Phoenix Chat with Manifold Architecture

## 1. Overview

CloudMsg is a high-performance, distributed Phoenix chat application that implements Discord's Manifold architecture for efficient message broadcasting across Erlang nodes. It is designed to handle massive scale—supporting 100,000+ concurrent connections with minimal network overhead and linearizable message delivery guarantees.

## 2. Goals

- **Massive Scale**: Support 100,000+ concurrent connections per node
- **Network Efficiency**: Reduce packets/sec by 50% through message coalescing
- **Linearizability**: Maintain send/2 ordering guarantees across distributed nodes
- **Fault Tolerance**: Survive node failures without message loss
- **Low Latency**: Sub-100ms message delivery for 99th percentile

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Client Layer                                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Browser   │  │   Browser   │  │   Browser   │  │   Browser   │         │
│  │  (Phoenix   │  │  (Phoenix   │  │  (Phoenix   │  │  (Phoenix   │         │
│  │   Channel)  │  │   Channel)  │  │   Channel)  │  │   Channel)  │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         │                │                │                │                │
│         └────────────────┴────────────────┴────────────────┘                │
│                          │                                                  │
│                          ▼                                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      Phoenix Endpoint (Cowboy)                       │   │
│  │              WebSocket handling with channel multiplexing            │   │
│  └────────────────────────────────┬────────────────────────────────────┘    │
│                                   │                                         │
└───────────────────────────────────┼─────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Manifold PubSub Layer                              │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    CloudMsg.PubSub (API Layer)                      │    │
│  │         broadcast(room_id, message) │ subscribe(room_id, pid)       │    │
│  └─────────────────────────────┬───────────────────────────────────────┘    │
│                                │                                            │
│                                ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    CloudMsg.Router (Partitioner)                    │    │
│  │        Groups subscribers by node, routes to remote partitioners    │    │
│  └─────────────────────────────┬───────────────────────────────────────┘    │
│                                │                                            │
│         ┌──────────────────────┼──────────────────────┐                     │
│         │                      │                      │                     │
│         ▼                      ▼                      ▼                     │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐                  │
│  │ Partitioner │      │ Partitioner │      │ Partitioner │   (1 per node)   │
│  │  Node A     │      │  Node B     │      │  Node C     │                  │
│  └──────┬──────┘      └──────┬──────┘      └──────┬──────┘                  │
│         │                    │                    │                         │
│         ▼                    ▼                    ▼                         │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐                  │
│  │   Worker    │      │   Worker    │      │   Worker    │   (N per core)   │
│  │   Pool      │      │   Pool      │      │   Pool      │                  │
│  └──────┬──────┘      └──────┬──────┘      └──────┬──────┘                  │
│         │                    │                    │                         │
└─────────┼────────────────────┼────────────────────┼─────────────────────────┘
          │                    │                    │
          ▼                    ▼                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Session Registry                                  │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                 CloudMsg.Session.Registry (ETS-backed)              │    │
│  │                                                                     │    │
│  │   room_id_123 ──→ [pid@node_a, pid@node_b, pid@node_c, ...]         │    │
│  │   room_id_456 ──→ [pid@node_a, pid@node_d, ...]                     │    │
│  │                                                                     │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                CloudMsg.Session.Presence (CRDT-based)               │    │
│  │                                                                     │    │
│  │   Tracks online/offline state with conflict-free reconciliation     │    │
│  │                                                                     │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4. Core Components

### 4.1 CloudMsg.PubSub

The public API for publishing and subscribing to chat rooms. Replaces Phoenix.PubSub with Manifold-based broadcasting.

```elixir
defmodule CloudMsg.PubSub do
  @spec subscribe(String.t(), pid()) :: :ok | {:error, term()}
  @spec broadcast(String.t(), term()) :: :ok
  @spec unsubscribe(String.t(), pid()) :: :ok
end
```

### 4.2 CloudMsg.Router (Partitioner Pattern)

Routes messages to the appropriate partitioner based on subscriber node location.

**Responsibilities:**
- Groups subscriber PIDs by their Erlang node
- Routes messages to `CloudMsg.Partitioner` on each node
- Handles `:binary` pack_mode for large message optimization
- Consistent hashing for partition selection

```elixir
defmodule CloudMsg.Router do
  use GenServer
  
  # Maximum 32 partitioners per node
  @max_partitioners 32
  @partitioners min(Application.get_env(:cloudmsg, :partitioners, 1), @max_partitioners)
  
  # Workers per partitioner = number of CPU cores
  @workers_per_partitioner Application.get_env(:cloudmsg, :workers_per_partitioner, System.schedulers_online())
end
```

### 4.3 CloudMsg.Partitioner

Per-node message distributor that partitions work across CPU cores.

**Key Behaviors:**
- Consistently hashes PIDs using `:erlang.phash2/2`
- Groups PIDs by number of cores
- Distributes to `CloudMsg.Worker` processes
- Maintains linearizability through ordered delivery
- Hibernates after inactivity to reduce memory footprint

**Process Flags:**
- `:trap_exit` - Handle worker crashes gracefully
- `:message_queue_data, :off_heap` - Reduce GC pressure

### 4.4 CloudMsg.Worker

Final-stage message delivery process.

**Responsibilities:**
- Unpacks messages (handles `:binary` and `:etf` modes)
- Calls `Kernel.send/2` to deliver to subscriber PIDs
- Hibernates to minimize memory usage

### 4.5 CloudMsg.Sender (Optional Offload Pattern)

Pool of processes for offloading large message sends from caller.

**Use Cases:**
- Very large messages (> 1MB)
- When send cost < distribution cost
- Configurable pool size: `config :cloudmsg, senders: 64`

**Linearizability Guarantee:**
- Same caller PID → Same Sender process
- Never mix offloaded and non-offloaded sends to same recipients

### 4.6 CloudMsg.Session.Registry

ETS-backed registry mapping room IDs to subscriber PIDs.

```elixir
# Table structure:
# {room_id, [pid()]} - Set of subscribers per room
# {pid, [room_id]} - Reverse index for fast unsubscribe
```

### 4.7 CloudMsg.Session.Presence

CRDT-based presence tracking for online/offline status.

**Features:**
- Conflict-free replicated data type for distributed consistency
- Heartbeat-based with automatic cleanup
- Metadata support (joined_at, typing status, etc.)

## 5. Message Flow

### 5.1 Subscribe Flow

```
1. Client joins room "lobby" via Phoenix Channel
2. CloudMsg.Channel calls PubSub.subscribe("lobby", self())
3. Registry adds pid to ETS table for "lobby"
4. Presence broadcasts join event to all "lobby" subscribers
```

### 5.2 Broadcast Flow (The Manifold Pattern)

```
1. User sends message to room "lobby"
2. PubSub.broadcast("lobby", {:chat_msg, user, text})
3. Router groups subscribers by node:
   
   Node A: [pid1, pid2, pid3]
   Node B: [pid4, pid5]
   Node C: [pid6, pid7, pid8, pid9]

4. Router sends 3 messages (one per node) instead of 9 individual sends
5. Each Partitioner hashes PIDs and distributes to Workers
6. Workers call Kernel.send/2 for final delivery
7. Phoenix Channels receive message and push to WebSockets
```

### 5.3 Large Message Optimization

```elixir
# For messages > 1MB, use binary pack mode
PubSub.broadcast("lobby", large_message, pack_mode: :binary)

# For extremely large broadcasts, use offload mode
PubSub.broadcast("lobby", huge_message, send_mode: :offload)
```

## 6. Data Structures

### 6.1 Registry ETS Tables

```elixir
# cloudmsg_room_subscribers (bag table)
# Key: room_id (String.t)
# Value: {pid, metadata}

# cloudmsg_pid_rooms (set table)
# Key: pid
# Value: [room_id] - list of subscribed rooms
```

### 6.2 Presence CRDT

```elixir
%CloudMsg.Presence.State{
  joins: %{pid => %{metas: [%{phx_ref: ..., online_at: ...}]}},
  leaves: %{},
  clock: %CloudMsg.Presence.Clock{}
}
```

## 7. Configuration

```elixir
# config/runtime.exs
config :cloudmsg, :manifold,
  # Number of partitioners (max 32)
  partitioners: 8,
  
  # Workers per partitioner (default: System.schedulers_online())
  workers_per_partitioner: 8,
  
  # Sender pool size for offload mode (max 128)
  senders: 64,
  
  # Hibernate after delay + random jitter
  hibernate_delay: 60_000,
  hibernate_jitter: 30_000,
  
  # Message size threshold for automatic binary packing
  auto_binary_threshold: 1_048_576,  # 1MB
  
  # Presence heartbeat interval
  presence_heartbeat_interval: 30_000

config :cloudmsg, :limits,
  # Max connections per room
  max_room_size: 10_000,
  
  # Max rooms per node
  max_rooms_per_node: 100_000,
  
  # Rate limit: messages per room per second
  room_rate_limit: 100,
  
  # Message size limit
  max_message_size: 8_388_608  # 8MB
```

## 8. Phoenix Integration

### 8.1 Channel Module

```elixir
defmodule CloudMsgWeb.ChatChannel do
  use CloudMsgWeb, :channel
  alias CloudMsg.PubSub
  alias CloudMsg.Presence

  def join("chat:" <> room_id, _params, socket) do
    send(self(), :after_join)
    {:ok, assign(socket, :room_id, room_id)}
  end

  def handle_info(:after_join, socket) do
    room_id = socket.assigns.room_id
    
    # Subscribe to Manifold PubSub
    PubSub.subscribe(room_id, self())
    
    # Track presence
    Presence.track(socket, socket.assigns.user_id, %{
      online_at: System.system_time(:second)
    })
    
    {:noreply, socket}
  end

  # Handle broadcasts from Manifold
  def handle_info(%Phoenix.Socket.Broadcast{} = msg, socket) do
    push(socket, "new_msg", msg.payload)
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    PubSub.unsubscribe(socket.assigns.room_id, self())
    :ok
  end
end
```

### 8.2 Socket Configuration

```elixir
defmodule CloudMsgWeb.UserSocket do
  use Phoenix.Socket
  
  # Set Manifold partitioner key based on user for consistency
  def connect(params, socket, _connect_info) do
    user_id = params["user_id"]
    CloudMsg.Router.set_partitioner_key(user_id)
    
    {:ok, assign(socket, :user_id, user_id)}
  end
end
```

## 9. Deployment Architecture

### 9.1 Multi-Node Setup

```
┌─────────────────────────────────────────────────────────────────┐
│                        Load Balancer                            │
│                    (Sticky sessions via IP hash)                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│   Node A      │◄──►│   Node B      │◄──►│   Node C      │
│  (Erlang)     │   │  (Erlang)     │   │  (Erlang)     │
│  (Phoenix)    │   │  (Phoenix)    │   │  (Phoenix)    │
│  (Manifold)   │   │  (Manifold)   │   │  (Manifold)   │
└───────────────┘   └───────────────┘   └───────────────┘
       │                   │                   │
       └───────────────────┴───────────────────┘
               Distributed Erlang Mesh
```

### 9.2 Node Connection Strategy

```elixir
# lib/cloudmsg/application.ex
children = [
  # Manifold supervision tree
  CloudMsg.Manifold.Supervisor,
  
  # Registry and Presence
  CloudMsg.Session.Registry,
  CloudMsg.Session.Presence,
  
  # Phoenix Endpoint
  CloudMsgWeb.Endpoint
]
```

## 10. Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Connections per node | 100,000+ | Limited by file descriptors/ports |
| Message throughput | 500,000 msg/sec/node | Fan-out of 1:10 |
| Broadcast latency (p99) | < 100ms | End-to-end from sender to receiver |
| Memory per connection | < 5KB | Including channel state |
| Network reduction | 50% | Compared to naive send/2 loop |
| Recovery time | < 5s | Node failure detection and recovery |

## 11. Testing Strategy

### 11.1 Unit Tests

- Partitioner consistent hashing correctness
- Worker message delivery ordering
- Registry add/remove operations
- Presence CRDT merge operations

### 11.2 Integration Tests

- Multi-node broadcast delivery
- Node failure handling
- Large message handling
- Rate limiting enforcement

### 11.3 Load Tests

```elixir
# test/load/broadcast_test.exs
Benchee.run(%{
  "manifold_broadcast" => fn ->
    pids = for _ <- 1..10000, do: spawn(fn -> :ok end)
    CloudMsg.PubSub.broadcast(pids, :test_message)
  end,
  "naive_broadcast" => fn ->
    pids = for _ <- 1..10000, do: spawn(fn -> :ok end)
    for pid <- pids, do: Kernel.send(pid, :test_message)
  end
})
```

## 12. Monitoring & Observability

### 12.1 Telemetry Events

```elixir
# Manifold metrics
[:cloudmsg, :manifold, :broadcast, :start]
[:cloudmsg, :manifold, :broadcast, :stop]
[:cloudmsg, :manifold, :broadcast, :exception]

# Router metrics
[:cloudmsg, :router, :group_by_node]
[:cloudmsg, :router, :partition]

# Partitioner metrics
[:cloudmsg, :partitioner, :queue_length]

# Worker metrics
[:cloudmsg, :worker, :send_duration]

# Presence metrics
[:cloudmsg, :presence, :diff, :size]
```

### 12.2 Key Metrics to Track

- `broadcast_duration_ms`: Time from broadcast call to worker send
- `packets_out_per_broadcast`: Network packets per broadcast operation
- `partitioner_queue_length`: Message queue depth (alert if > 1000)
- `worker_hibernate_rate`: Frequency of worker hibernation
- `presence_merge_duration_ms`: CRDT merge performance
- `registry_ets_memory`: ETS table memory usage

## 13. Security Considerations

- **Authentication**: JWT validation on channel join
- **Authorization**: Room membership checks before subscribe
- **Rate Limiting**: Per-user and per-room message limits
- **Message Sanitization**: HTML escaping for user content
- **Transport Security**: TLS 1.3 for WebSocket connections

## 14. Future Enhancements

1. **Selective Broadcasting**: Filter recipients based on metadata
2. **Message Persistence**: Integration with persistent message stores
3. **Backpressure**: Flow control for slow consumers
4. **Sharding**: Geographic distribution with eventual consistency
5. **Compression**: Message compression for cross-region traffic

## 15. References

- [Manifold Repository](https://github.com/discord/manifold)
- [Discord Engineering Blog](https://discord.com/blog)
- [Erlang Distribution Protocol](https://www.erlang.org/doc/apps/erts/erl_dist_protocol.html)
- [Phoenix PubSub Documentation](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html)
- [Phoenix Channels Guide](https://hexdocs.pm/phoenix/channels.html)

---

**Version**: 1.0.0  
**Last Updated**: 2026-02-23  
**Status**: Draft - Ready for Implementation

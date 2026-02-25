defmodule Crossroad.PubSub do
  @moduledoc """
  Public API for the CloudMsg publish-subscribe system.

  Provides functions to subscribe to rooms, broadcast messages to rooms,
  and unsubscribe from rooms. Uses the Manifold Router for efficient
  message broadcasting across distributed nodes.

  ## Examples

      # Subscribe to a room
      CloudMsg.PubSub.subscribe("room:lobby", self())

      # Broadcast a message to all subscribers
      CloudMsg.PubSub.broadcast("room:lobby", {:chat_msg, %{user: "alice", text: "Hello!"}})

      # Unsubscribe from a room
      CloudMsg.PubSub.unsubscribe("room:lobby", self())
  """

  alias Crossroad.{Router, Session.Registry}

  @doc """
  Subscribes a PID to receive messages from a room.

  ## Parameters

  - `room_id` - The unique identifier for the room (string)
  - `pid` - The process ID to subscribe (defaults to calling process)

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec subscribe(String.t(), pid()) :: :ok | {:error, term()}
  def subscribe(room_id, pid \\ self()) when is_binary(room_id) and is_pid(pid) do
    Registry.subscribe(room_id, pid)
  end

  @doc """
  Broadcasts a message to all subscribers of a room.

  Uses the Manifold Router to efficiently distribute messages across nodes.

  ## Parameters

  - `room_id` - The room to broadcast to
  - `message` - The message to broadcast
  - `opts` - Options for the broadcast:
    - `:pack_mode` - `:binary` for large messages, `:etf` for default
    - `:send_mode` - `:offload` to use sender pool

  ## Returns

  - `:ok` on success
  """
  @spec broadcast(String.t(), term(), Keyword.t()) :: :ok
  def broadcast(room_id, message, opts \\ []) when is_binary(room_id) do
    case Registry.get_subscribers(room_id) do
      [] ->
        :ok

      pids when is_list(pids) ->
        Router.send(pids, {:crossroad_broadcast, room_id, message}, opts)
    end
  end

  @doc """
  Unsubscribes a PID from a room.

  ## Parameters

  - `room_id` - The room to unsubscribe from
  - `pid` - The process ID to unsubscribe (defaults to calling process)

  ## Returns

  - `:ok` on success
  """
  @spec unsubscribe(String.t(), pid()) :: :ok
  def unsubscribe(room_id, pid \\ self()) when is_binary(room_id) and is_pid(pid) do
    Registry.unsubscribe(room_id, pid)
  end

  @doc """
  Lists all rooms that a PID is subscribed to.

  ## Parameters

  - `pid` - The process ID to look up (defaults to calling process)

  ## Returns

  - List of room IDs
  """
  @spec list_subscriptions(pid()) :: [String.t()]
  def list_subscriptions(pid \\ self()) when is_pid(pid) do
    Registry.get_pid_rooms(pid)
  end

  @doc """
  Lists all subscribers for a room.

  ## Parameters

  - `room_id` - The room to look up

  ## Returns

  - List of subscriber PIDs
  """
  @spec list_subscribers(String.t()) :: [pid()]
  def list_subscribers(room_id) when is_binary(room_id) do
    Registry.get_subscribers(room_id)
  end

  @doc """
  Returns the number of subscribers in a room.

  ## Parameters

  - `room_id` - The room to count subscribers for

  ## Returns

  - Integer count of subscribers
  """
  @spec subscriber_count(String.t()) :: non_neg_integer()
  def subscriber_count(room_id) when is_binary(room_id) do
    Registry.subscriber_count(room_id)
  end
end

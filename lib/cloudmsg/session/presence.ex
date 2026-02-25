defmodule Cloudmsg.Session.Presence do
  @moduledoc """
  CRDT-based presence tracking for online/offline status.

  Uses a simplified conflict-free replicated data type for distributed
  consistency. Tracks when users join/leave rooms with metadata support
  (joined_at, typing status, etc.).

  ## Usage

      Presence.track(socket, user_id, %{online_at: System.system_time(:second)})
      Presence.list("room:lobby") # Returns all present users
  """

  use GenServer

  require Logger

  @heartbeat_interval 30_000

  # CRDT State structure
  defmodule State do
    defstruct joins: %{}, leaves: %{}, clock: 0

    @type t :: %__MODULE__{
            joins: map(),
            leaves: map(),
            clock: non_neg_integer()
          }
  end

  ## Client API

  @doc """
  Starts the Presence process.
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Tracks a socket's presence in a room.

  ## Parameters

  - `socket` - The Phoenix.Socket
  - `key` - Unique identifier for the user (e.g., user_id)
  - `meta` - Map of metadata about the user's presence

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec track(Phoenix.Socket.t(), term(), map()) :: :ok | {:error, term()}
  def track(socket, key, meta) when is_map(meta) do
    room_id = socket.topic
    track_pid(socket.channel_pid, key, meta, room_id)
  end

  @doc """
  Tracks a PID's presence directly.
  """
  @spec track_pid(pid(), term(), map(), String.t()) :: :ok | {:error, term()}
  def track_pid(pid, key, meta, room_id) when is_pid(pid) and is_map(meta) and is_binary(room_id) do
    GenServer.call(__MODULE__, {:track, pid, key, meta, room_id})
  end

  @doc """
  Untracks a PID's presence.
  """
  @spec untrack(pid(), String.t()) :: :ok
  def untrack(pid, room_id) when is_pid(pid) and is_binary(room_id) do
    GenServer.call(__MODULE__, {:untrack, pid, room_id})
  end

  @doc """
  Lists all presences in a room.

  Returns a map of keys to their metadata.
  """
  @spec list(String.t()) :: %{term() => map()}
  def list(room_id) when is_binary(room_id) do
    GenServer.call(__MODULE__, {:list, room_id})
  end

  @doc """
  Gets the presence count for a room.
  """
  @spec count(String.t()) :: non_neg_integer()
  def count(room_id) when is_binary(room_id) do
    GenServer.call(__MODULE__, {:count, room_id})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Start heartbeat timer
    schedule_heartbeat()

    {:ok, %{
      # room_id => %State{}
      rooms: %{},
      # pid => [{room_id, key, ref}]
      pids: %{}
    }}
  end

  @impl true
  def handle_call({:track, pid, key, meta, room_id}, _from, state) do
    if Process.alive?(pid) do
      ref = Process.monitor(pid)

      # Update pid tracking
      pid_tracks = Map.get(state.pids, pid, [])
      new_pid_tracks = [{room_id, key, ref} | pid_tracks]

      # Update room state
      room_state = Map.get(state.rooms, room_id, %State{})

      joins =
        Map.update(room_state.joins, key, %{metas: [meta]}, fn existing ->
          %{existing | metas: [meta | existing.metas]}
        end)

      new_room_state = %{room_state | joins: joins, clock: room_state.clock + 1}

      new_state =
        state
        |> put_in([:pids, pid], new_pid_tracks)
        |> put_in([:rooms, room_id], new_room_state)

      # Broadcast the join
      broadcast_diff(room_id, %{joins: %{key => joins[key]}, leaves: %{}})

      {:reply, :ok, new_state}
    else
      {:reply, {:error, :pid_not_alive}, state}
    end
  end

  @impl true
  def handle_call({:untrack, pid, room_id}, _from, state) do
    # Find and remove the track for this pid/room
    pid_tracks = Map.get(state.pids, pid, [])

    case Enum.find(pid_tracks, fn {r, _key, _ref} -> r == room_id end) do
      nil ->
        {:reply, :ok, state}

      {^room_id, key, ref} ->
        Process.demonitor(ref)

        new_pid_tracks = Enum.reject(pid_tracks, fn {r, _k, _ref} -> r == room_id end)

        # Update room state
        room_state = Map.get(state.rooms, room_id, %State{})

        {join_meta, new_joins} = Map.pop(room_state.joins, key, %{metas: []})

        leaves = Map.put(room_state.leaves, key, join_meta)

        new_room_state = %{
          room_state
          | joins: new_joins,
            leaves: leaves,
            clock: room_state.clock + 1
        }

        new_state =
          state
          |> put_in([:pids, pid], new_pid_tracks)
          |> put_in([:rooms, room_id], new_room_state)

        # Broadcast the leave
        broadcast_diff(room_id, %{joins: %{}, leaves: %{key => join_meta}})

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:list, room_id}, _from, state) do
    room_state = Map.get(state.rooms, room_id, %State{})

    result =
      for {key, %{metas: metas}} <- room_state.joins, into: %{} do
        {key, List.first(metas)}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:count, room_id}, _from, state) do
    room_state = Map.get(state.rooms, room_id, %State{})
    count = map_size(room_state.joins)
    {:reply, count, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    # Clean up when a tracked process dies
    pid_tracks = Map.get(state.pids, pid, [])

    new_state =
      Enum.reduce(pid_tracks, state, fn {room_id, key, track_ref}, acc ->
        if track_ref == ref do
          # Update room state
          room_state = Map.get(acc.rooms, room_id, %State{})
          {join_meta, new_joins} = Map.pop(room_state.joins, key, %{metas: []})

          leaves = Map.put(room_state.leaves, key, join_meta)

          new_room_state = %{
            room_state
            | joins: new_joins,
              leaves: leaves,
              clock: room_state.clock + 1
          }

          # Broadcast the leave
          broadcast_diff(room_id, %{joins: %{}, leaves: %{key => join_meta}})

          put_in(acc.rooms[room_id], new_room_state)
        else
          acc
        end
      end)

    new_pids = Map.delete(new_state.pids, pid)
    {:noreply, %{new_state | pids: new_pids}}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    # Periodic cleanup of stale leaves
    schedule_heartbeat()

    # Clear leaves after they've been broadcast
    new_rooms =
      for {room_id, room_state} <- state.rooms, into: %{} do
        {room_id, %{room_state | leaves: %{}}}
      end

    {:noreply, %{state | rooms: new_rooms}}
  end

  ## Private Functions

  defp schedule_heartbeat() do
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
  end

  defp broadcast_diff(room_id, diff) do
    # Broadcast presence diff to all subscribers
    Cloudmsg.PubSub.broadcast(
      room_id,
      {:presence_diff, diff}
    )
  end
end

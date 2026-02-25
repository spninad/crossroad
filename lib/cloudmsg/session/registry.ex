defmodule Cloudmsg.Session.Registry do
  @moduledoc """
  ETS-backed registry for mapping room IDs to subscriber PIDs.

  Maintains two ETS tables:
  - `:cloudmsg_room_subscribers` - Maps room_id to {pid, metadata} pairs (bag table)
  - `:cloudmsg_pid_rooms` - Maps pid to list of room_ids for fast cleanup (set table)

  All operations are atomic and support concurrent access.
  """

  use GenServer

  require Logger

  @room_table :cloudmsg_room_subscribers
  @pid_table :cloudmsg_pid_rooms

  ## Client API

  @doc """
  Starts the Registry process and initializes ETS tables.
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribes a PID to a room.
  """
  @spec subscribe(String.t(), pid()) :: :ok
  def subscribe(room_id, pid) when is_binary(room_id) and is_pid(pid) do
    # Check if pid is alive before subscribing
    if Process.alive?(pid) do
      :ets.insert(@room_table, {room_id, pid, %{}})

      # Update reverse index
      case :ets.lookup(@pid_table, pid) do
        [{^pid, rooms}] ->
          :ets.insert(@pid_table, {pid, [room_id | rooms]})

        [] ->
          :ets.insert(@pid_table, {pid, [room_id]})
      end

      # Monitor the pid for cleanup
      GenServer.call(__MODULE__, {:monitor, pid})
    else
      :ok
    end
  end

  @doc """
  Unsubscribes a PID from a room.
  """
  @spec unsubscribe(String.t(), pid()) :: :ok
  def unsubscribe(room_id, pid) when is_binary(room_id) and is_pid(pid) do
    # Remove from room table
    :ets.match_delete(@room_table, {room_id, pid, :_})

    # Update reverse index
    case :ets.lookup(@pid_table, pid) do
      [{^pid, rooms}] ->
        new_rooms = List.delete(rooms, room_id)

        if new_rooms == [] do
          :ets.delete(@pid_table, pid)
        else
          :ets.insert(@pid_table, {pid, new_rooms})
        end

      [] ->
        :ok
    end

    :ok
  end

  @doc """
  Gets all subscribers for a room.
  """
  @spec get_subscribers(String.t()) :: [pid()]
  def get_subscribers(room_id) when is_binary(room_id) do
    @room_table
    |> :ets.lookup(room_id)
    |> Enum.map(fn {_room_id, pid, _metadata} -> pid end)
    |> Enum.filter(&Process.alive?/1)
  end

  @doc """
  Gets all rooms a PID is subscribed to.
  """
  @spec get_pid_rooms(pid()) :: [String.t()]
  def get_pid_rooms(pid) when is_pid(pid) do
    case :ets.lookup(@pid_table, pid) do
      [{^pid, rooms}] -> rooms
      [] -> []
    end
  end

  @doc """
  Returns the number of subscribers in a room.
  """
  @spec subscriber_count(String.t()) :: non_neg_integer()
  def subscriber_count(room_id) when is_binary(room_id) do
    room_id
    |> get_subscribers()
    |> length()
  end

  @doc """
  Unsubscribes a PID from all rooms. Called when a process terminates.
  """
  @spec unsubscribe_all(pid()) :: :ok
  def unsubscribe_all(pid) when is_pid(pid) do
    rooms = get_pid_rooms(pid)

    for room_id <- rooms do
      :ets.match_delete(@room_table, {room_id, pid, :_})
    end

    :ets.delete(@pid_table, pid)
    GenServer.call(__MODULE__, {:demonitor, pid})

    :ok
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Create bag table for room subscribers
    :ets.new(@room_table, [
      :bag,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Create set table for pid reverse index
    :ets.new(@pid_table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{monitors: %{}}}
  end

  @impl true
  def handle_call({:monitor, pid}, _from, state) when is_pid(pid) do
    monitors =
      if Map.has_key?(state.monitors, pid) do
        state.monitors
      else
        ref = Process.monitor(pid)
        Map.put(state.monitors, pid, ref)
      end

    {:reply, :ok, %{state | monitors: monitors}}
  end

  @impl true
  def handle_call({:demonitor, pid}, _from, state) when is_pid(pid) do
    monitors =
      case Map.pop(state.monitors, pid) do
        {nil, m} -> m
        {ref, m} ->
          Process.demonitor(ref)
          m
      end

    {:reply, :ok, %{state | monitors: monitors}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Clean up subscriptions when a process dies
    unsubscribe_all(pid)

    monitors = Map.delete(state.monitors, pid)
    {:noreply, %{state | monitors: monitors}}
  end
end

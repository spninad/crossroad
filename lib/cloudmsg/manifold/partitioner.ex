defmodule Crossroad.Manifold.Partitioner do
  @moduledoc """
  Per-node message distributor that partitions work across CPU cores.

  Receives messages from the Router, partitions PIDs by consistent hashing,
  and distributes to Worker processes for final delivery.
  Maintains linearizability through ordered delivery.
  """

  use GenServer

  require Logger

  alias Crossroad.Manifold.{Worker, Utils}

  @gen_module Application.compile_env(:crossroad_manifold, :gen_module, GenServer)

  ## Client API

  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(partitions, opts \\ []) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [partitions, opts]},
      type: :supervisor
    }
  end

  @spec start_link(integer(), Keyword.t()) :: GenServer.on_start()
  def start_link(partitions, opts \\ []) do
    GenServer.start_link(__MODULE__, partitions, opts)
  end

  @spec send(GenServer.server(), [pid()], term()) :: :ok
  def send(partitioner, pids, message) do
    @gen_module.cast(partitioner, {:send, pids, message})
  end

  ## Server Callbacks

  @impl true
  def init(partitions) do
    # Set optimal process flags for high-throughput message handling
    Process.flag(:trap_exit, true)
    Process.flag(:message_queue_data, :off_heap)

    workers =
      for _ <- 0..partitions do
        {:ok, pid} = Worker.start_link()
        pid
      end

    schedule_next_hibernate()
    {:ok, List.to_tuple(workers)}
  end

  @impl true
  def terminate(_reason, _state), do: :ok

  @impl true
  def handle_call(:which_children, _from, state) do
    children =
      for pid <- Tuple.to_list(state), is_pid(pid) do
        {:undefined, pid, :worker, [Worker]}
      end

    {:reply, children, state}
  end

  @impl true
  def handle_call(:count_children, _from, state) do
    {:reply,
     [
       specs: 1,
       active: tuple_size(state),
       supervisors: 0,
       workers: tuple_size(state)
     ], state}
  end

  @impl true
  def handle_call(_message, _from, state) do
    {:reply, :error, state}
  end

  # Specialize handling cast to a single pid
  @impl true
  def handle_cast({:send, [pid], message}, state) do
    partition = Utils.partition_for(pid, tuple_size(state))
    Worker.send(elem(state, partition), [pid], message)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:send, pids, message}, state) do
    partitions = tuple_size(state)
    pids_by_partition = Utils.partition_pids(pids, partitions)
    do_send(message, pids_by_partition, state, 0, partitions)
    {:noreply, state}
  end

  @impl true
  def handle_cast(_message, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    Logger.warning("manifold worker exited: #{inspect(reason)}")

    state =
      state
      |> Tuple.to_list()
      |> Enum.map(fn
        ^pid ->
          {:ok, new_pid} = Worker.start_link()
          new_pid

        p ->
          p
      end)
      |> List.to_tuple()

    {:noreply, state}
  end

  @impl true
  def handle_info(:hibernate, state) do
    schedule_next_hibernate()
    {:noreply, state, :hibernate}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp do_send(_message, _pids_by_partition, _workers, partitions, partitions), do: :ok

  defp do_send(message, pids_by_partition, workers, partition, partitions) do
    pids = elem(pids_by_partition, partition)

    if pids != [] do
      Worker.send(elem(workers, partition), pids, message)
    end

    do_send(message, pids_by_partition, workers, partition + 1, partitions)
  end

  defp schedule_next_hibernate() do
    Process.send_after(self(), :hibernate, Utils.next_hibernate_delay())
  end
end

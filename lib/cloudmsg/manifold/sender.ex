defmodule Crossroad.Manifold.Sender do
  @moduledoc """
  Pool of processes for offloading large message sends from the caller.

  When send_mode is :offload, messages are sent to a pool of Sender processes
  rather than directly from the caller. This is useful for very large messages
  where the cost of sending < cost of distribution.

  Linearizability is maintained by always routing the same caller PID to the
  same Sender process.
  """

  use GenServer

  alias Crossroad.Manifold.Utils

  @gen_module Application.compile_env(:crossroad, :gen_module, GenServer)

  ## Client API

  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [:ok, opts]},
      type: :supervisor
    }
  end

  @spec start_link(:ok, Keyword.t()) :: GenServer.on_start()
  def start_link(:ok, opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @spec send(GenServer.server(), GenServer.server(), [pid()], term(), atom()) :: :ok
  def send(sender, partitioner, pids, message, pack_mode) do
    @gen_module.cast(sender, {:send, partitioner, pids, message, pack_mode})
  end

  ## Server Callbacks

  @impl true
  def init(:ok) do
    # Set optimal process flags
    Process.flag(:message_queue_data, :off_heap)
    schedule_next_hibernate()
    {:ok, nil}
  end

  @impl true
  def handle_cast({:send, partitioner, pids, message, pack_mode}, nil) do
    message = Utils.pack_message(pack_mode, message)

    grouped_by =
      Utils.group_by(pids, fn
        nil -> nil
        pid -> node(pid)
      end)

    for {node, node_pids} <- grouped_by, node != nil do
      Crossroad.Manifold.Partitioner.send({partitioner, node}, node_pids, message)
    end

    {:noreply, nil}
  end

  @impl true
  def handle_cast(_message, nil) do
    {:noreply, nil}
  end

  @impl true
  def handle_info(:hibernate, nil) do
    schedule_next_hibernate()
    {:noreply, nil, :hibernate}
  end

  @impl true
  def handle_info(_message, nil) do
    {:noreply, nil}
  end

  defp schedule_next_hibernate() do
    Process.send_after(self(), :hibernate, Utils.next_hibernate_delay())
  end
end

defmodule Crossroad.Manifold.Worker do
  @moduledoc """
  Final-stage message delivery worker.
  Receives partitioned messages from the Partitioner and calls Kernel.send/2
  to deliver to subscriber PIDs. Hibernates to minimize memory usage.
  """

  use GenServer

  alias Crossroad.Manifold.Utils

  ## Client API

  @spec start_link :: GenServer.on_start()
  def start_link, do: GenServer.start_link(__MODULE__, [])

  @spec send(pid, [pid], term) :: :ok
  def send(pid, pids, message), do: GenServer.cast(pid, {:send, pids, message})

  ## Server Callbacks

  @impl true
  @spec init([]) :: {:ok, nil}
  def init([]) do
    schedule_next_hibernate()
    {:ok, nil}
  end

  @impl true
  def handle_cast({:send, [pid], message}, nil) do
    message = Utils.unpack_message(message)
    Kernel.send(pid, message)
    {:noreply, nil}
  end

  @impl true
  def handle_cast({:send, pids, message}, nil) do
    message = Utils.unpack_message(message)
    for pid <- pids, do: Kernel.send(pid, message)
    {:noreply, nil}
  end

  @impl true
  def handle_cast(_message, nil), do: {:noreply, nil}

  @impl true
  def handle_info(:hibernate, nil) do
    schedule_next_hibernate()
    {:noreply, nil, :hibernate}
  end

  defp schedule_next_hibernate() do
    Process.send_after(self(), :hibernate, Utils.next_hibernate_delay())
  end
end

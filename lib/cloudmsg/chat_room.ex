defmodule CloudMsg.ChatRoom do
  use GenServer
  
  defstruct [:name, :messages, :subscribers]
  
  def start_link(room_name) do
    GenServer.start_link(__MODULE__, room_name, name: via_tuple(room_name))
  end
  
  def add_message(room_name, message) do
    GenServer.call(via_tuple(room_name), {:add_message, message})
  end
  
  def get_messages(room_name) do
    GenServer.call(via_tuple(room_name), :get_messages)
  end
  
  def subscribe(room_name, subscriber_pid) do
    GenServer.cast(via_tuple(room_name), {:subscribe, subscriber_pid})
  end
  
  def unsubscribe(room_name, subscriber_pid) do
    GenServer.cast(via_tuple(room_name), {:unsubscribe, subscriber_pid})
  end
  
  @impl true
  def init(room_name) do
    {:ok, %__MODULE__{
      name: room_name,
      messages: [],
      subscribers: MapSet.new()
    }}
  end
  
  @impl true
  def handle_call({:add_message, message}, _from, state) do
    id = generate_id()
    message_with_meta = Map.merge(message, %{
      id: id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      room: state.name
    })
    
    new_messages = [message_with_meta | state.messages]
    new_state = %{state | messages: new_messages}
    
    # Broadcast to all subscribers
    Enum.each(state.subscribers, fn pid ->
      send(pid, {:new_message, message_with_meta})
    end)
    
    {:reply, {:ok, id}, new_state}
  end
  
  @impl true
  def handle_call(:get_messages, _from, state) do
    {:reply, Enum.reverse(state.messages), state}
  end
  
  @impl true
  def handle_cast({:subscribe, subscriber_pid}, state) do
    Process.monitor(subscriber_pid)
    new_subscribers = MapSet.put(state.subscribers, subscriber_pid)
    {:noreply, %{state | subscribers: new_subscribers}}
  end
  
  @impl true
  def handle_cast({:unsubscribe, subscriber_pid}, state) do
    new_subscribers = MapSet.delete(state.subscribers, subscriber_pid)
    {:noreply, %{state | subscribers: new_subscribers}}
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    new_subscribers = MapSet.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: new_subscribers}}
  end
  
  defp via_tuple(room_name) do
    {:via, Registry, {CloudMsg.RoomRegistry, room_name}}
  end
  
  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
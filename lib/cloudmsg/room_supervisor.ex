defmodule CloudMsg.RoomSupervisor do
  use DynamicSupervisor
  
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  def start_room(room_name) do
    child_spec = {CloudMsg.ChatRoom, room_name}
    
    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end
  
  def stop_room(room_name) do
    case Registry.lookup(CloudMsg.RoomRegistry, room_name) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> :ok
    end
  end
  
  def list_rooms do
    Registry.select(CloudMsg.RoomRegistry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
  end
  
  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
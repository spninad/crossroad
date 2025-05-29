defmodule CloudMsg.MessageStore do
  @moduledoc """
  Distributed message store that manages chat rooms and message routing.
  Each room runs as a separate process for high scalability.
  """
  
  def add_message(room_name, message) do
    ensure_room_exists(room_name)
    CloudMsg.ChatRoom.add_message(room_name, message)
  end
  
  def get_messages(room_name \\ "general") do
    ensure_room_exists(room_name)
    CloudMsg.ChatRoom.get_messages(room_name)
  end
  
  def get_message(id) do
    # For backward compatibility - search across all rooms
    CloudMsg.RoomSupervisor.list_rooms()
    |> Enum.find_value(fn room_name ->
      CloudMsg.ChatRoom.get_messages(room_name)
      |> Enum.find(&(&1.id == id))
    end)
  end
  
  def subscribe_to_room(room_name, subscriber_pid \\ self()) do
    ensure_room_exists(room_name)
    CloudMsg.ChatRoom.subscribe(room_name, subscriber_pid)
  end
  
  def unsubscribe_from_room(room_name, subscriber_pid \\ self()) do
    CloudMsg.ChatRoom.unsubscribe(room_name, subscriber_pid)
  end
  
  def list_rooms do
    CloudMsg.RoomSupervisor.list_rooms()
  end
  
  defp ensure_room_exists(room_name) do
    CloudMsg.RoomSupervisor.start_room(room_name)
  end
end
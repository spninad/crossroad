defmodule CloudMsgWeb.RoomChannelTest do
  use CloudMsgWeb.ChannelCase
  
  setup do
    # Clean up any existing rooms for isolated tests
    CloudMsg.RoomSupervisor.list_rooms()
    |> Enum.each(&CloudMsg.RoomSupervisor.stop_room/1)
    
    {:ok, _, socket} =
      CloudMsgWeb.UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(CloudMsgWeb.RoomChannel, "room:lobby")

    %{socket: socket}
  end

  test "ping replies with status ok", %{socket: socket} do
    ref = push(socket, "ping", %{"hello" => "there"})
    assert_reply ref, :ok, %{"hello" => "there"}
  end

  test "shout broadcasts to room:lobby", %{socket: socket} do
    push(socket, "new_msg", %{"body" => "hello", "user" => "testuser"})
    assert_broadcast "new_msg", %{content: "hello", user: "testuser"}
  end

  test "broadcasts are pushed to the client", %{socket: socket} do
    broadcast_from!(socket, "room:lobby", "new_msg", %{"body" => "hello"})
    assert_push "new_msg", %{"body" => "hello"}
  end
  
  test "get_messages returns room messages", %{socket: socket} do
    # Add a message first
    push(socket, "new_msg", %{"body" => "test message", "user" => "testuser"})
    
    ref = push(socket, "get_messages", %{})
    assert_reply ref, :ok, %{messages: messages}
    
    assert is_list(messages)
  end
end
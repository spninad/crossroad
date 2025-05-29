defmodule CloudMsg.MessageStoreTest do
  use ExUnit.Case
  
  alias CloudMsg.MessageStore
  
  setup do
    # Clean up any existing rooms for isolated tests
    CloudMsg.RoomSupervisor.list_rooms()
    |> Enum.each(&CloudMsg.RoomSupervisor.stop_room/1)
    
    :ok
  end
  
  test "adds message to default room" do
    message = %{content: "Hello World", user: "TestUser"}
    
    assert {:ok, id} = MessageStore.add_message("test_room", message)
    assert is_binary(id)
    assert String.length(id) == 16
  end
  
  test "retrieves messages from room" do
    message1 = %{content: "First message", user: "User1"}
    message2 = %{content: "Second message", user: "User2"}
    
    {:ok, _id1} = MessageStore.add_message("test_room", message1)
    {:ok, _id2} = MessageStore.add_message("test_room", message2)
    
    messages = MessageStore.get_messages("test_room")
    
    assert length(messages) == 2
    assert Enum.any?(messages, &(&1.content == "First message"))
    assert Enum.any?(messages, &(&1.content == "Second message"))
  end
  
  test "messages are isolated by room" do
    {:ok, _id1} = MessageStore.add_message("room1", %{content: "Room 1 message", user: "User1"})
    {:ok, _id2} = MessageStore.add_message("room2", %{content: "Room 2 message", user: "User2"})
    
    room1_messages = MessageStore.get_messages("room1")
    room2_messages = MessageStore.get_messages("room2")
    
    assert length(room1_messages) == 1
    assert length(room2_messages) == 1
    assert hd(room1_messages).content == "Room 1 message"
    assert hd(room2_messages).content == "Room 2 message"
  end
  
  test "lists all rooms" do
    MessageStore.add_message("room1", %{content: "Message 1", user: "User1"})
    MessageStore.add_message("room2", %{content: "Message 2", user: "User2"})
    MessageStore.add_message("room3", %{content: "Message 3", user: "User3"})
    
    rooms = MessageStore.list_rooms()
    
    assert "room1" in rooms
    assert "room2" in rooms
    assert "room3" in rooms
  end
  
  test "subscription to room receives new messages" do
    test_pid = self()
    room_name = "subscription_test"
    
    # Subscribe to the room
    MessageStore.subscribe_to_room(room_name, test_pid)
    
    # Add a message
    message = %{content: "Test subscription", user: "TestUser"}
    {:ok, _id} = MessageStore.add_message(room_name, message)
    
    # Should receive the message
    assert_receive {:new_message, received_message}
    assert received_message.content == "Test subscription"
    assert received_message.user == "TestUser"
    assert received_message.room == room_name
  end
  
  test "backward compatibility - get_message by id" do
    message = %{content: "Legacy test", user: "LegacyUser"}
    {:ok, id} = MessageStore.add_message("legacy_room", message)
    
    retrieved_message = MessageStore.get_message(id)
    assert retrieved_message.content == "Legacy test"
    assert retrieved_message.id == id
  end
end
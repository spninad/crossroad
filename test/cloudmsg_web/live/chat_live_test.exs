defmodule CloudMsgWeb.ChatLiveTest do
  use CloudMsgWeb.ConnCase
  
  import Phoenix.LiveViewTest
  
  setup do
    # Clean up any existing rooms for isolated tests
    CloudMsg.RoomSupervisor.list_rooms()
    |> Enum.each(&CloudMsg.RoomSupervisor.stop_room/1)
    
    :ok
  end
  
  test "disconnected and connected render", %{conn: conn} do
    {:ok, page_live, disconnected_html} = live(conn, ~p"/")
    
    assert disconnected_html =~ "CloudMsg Chat"
    assert render(page_live) =~ "CloudMsg Chat"
  end
  
  test "sends message and displays it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    
    # Send a message
    form = form(view, "#message-form", message: %{content: "Hello from test"})
    render_submit(form)
    
    # Message should appear in the chat
    assert render(view) =~ "Hello from test"
  end
  
  test "joins specific room", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/room/test-room")
    
    assert render(view) =~ "# test-room"
  end
  
  test "messages are isolated by room", %{conn: conn} do
    # Connect to room1
    {:ok, view1, _html} = live(conn, ~p"/room/room1")
    
    # Connect to room2  
    {:ok, view2, _html} = live(conn, ~p"/room/room2")
    
    # Send message to room1
    form1 = form(view1, "#message-form", message: %{content: "Room 1 message"})
    render_submit(form1)
    
    # Send message to room2
    form2 = form(view2, "#message-form", message: %{content: "Room 2 message"})
    render_submit(form2)
    
    # Each room should only see its own message
    assert render(view1) =~ "Room 1 message"
    refute render(view1) =~ "Room 2 message"
    
    assert render(view2) =~ "Room 2 message"
    refute render(view2) =~ "Room 1 message"
  end
end
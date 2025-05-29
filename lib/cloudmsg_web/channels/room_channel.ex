defmodule CloudMsgWeb.RoomChannel do
  use CloudMsgWeb, :channel
  
  @impl true
  def join("room:" <> room_name, payload, socket) do
    if authorized?(payload) do
      # Subscribe to the room process for real-time updates
      CloudMsg.MessageStore.subscribe_to_room(room_name)
      
      socket = assign(socket, :room, room_name)
      {:ok, %{status: "joined room #{room_name}"}, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Channels can be used in a request/response fashion
  # by sending replies to requests from the client
  @impl true
  def handle_in("new_msg", %{"body" => body, "user" => user}, socket) do
    room_name = socket.assigns.room
    
    message = %{
      content: body,
      user: user
    }
    
    case CloudMsg.MessageStore.add_message(room_name, message) do
      {:ok, _id} ->
        # Message will be broadcast via process subscription
        {:reply, {:ok, %{status: "message sent"}}, socket}
      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("get_messages", _payload, socket) do
    room_name = socket.assigns.room
    messages = CloudMsg.MessageStore.get_messages(room_name)
    {:reply, {:ok, %{messages: messages}}, socket}
  end

  # Handle messages from the room process
  @impl true
  def handle_info({:new_message, message}, socket) do
    push(socket, "new_msg", message)
    {:noreply, socket}
  end

  # Add authorization logic here as required.
  defp authorized?(_payload) do
    true
  end
end
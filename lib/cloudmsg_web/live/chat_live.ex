defmodule CloudMsgWeb.ChatLive do
  use CloudMsgWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    room = Map.get(params, "room", "general")
    username = generate_username()
    
    if connected?(socket) do
      CloudMsg.MessageStore.subscribe_to_room(room)
    end
    
    messages = CloudMsg.MessageStore.get_messages(room)
    rooms = CloudMsg.MessageStore.list_rooms()
    
    socket = 
      socket
      |> assign(:room, room)
      |> assign(:username, username)
      |> assign(:messages, messages)
      |> assign(:rooms, rooms)
      |> assign(:message_content, "")
      |> assign(:show_username_form, false)
    
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    room = Map.get(params, "room", "general")
    
    if room != socket.assigns.room do
      # Unsubscribe from old room and subscribe to new room
      CloudMsg.MessageStore.unsubscribe_from_room(socket.assigns.room)
      CloudMsg.MessageStore.subscribe_to_room(room)
      
      messages = CloudMsg.MessageStore.get_messages(room)
      
      socket = 
        socket
        |> assign(:room, room)
        |> assign(:messages, messages)
    else
      socket = socket
    end
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"content" => content}}, socket) do
    if String.trim(content) != "" do
      message = %{
        content: String.trim(content),
        user: socket.assigns.username
      }
      
      case CloudMsg.MessageStore.add_message(socket.assigns.room, message) do
        {:ok, _id} ->
          socket = assign(socket, :message_content, "")
          {:noreply, socket}
        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to send message")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_content", %{"message" => %{"content" => content}}, socket) do
    {:noreply, assign(socket, :message_content, content)}
  end

  @impl true
  def handle_event("change_username", _params, socket) do
    {:noreply, assign(socket, :show_username_form, true)}
  end

  @impl true
  def handle_event("save_username", %{"username" => %{"name" => name}}, socket) do
    username = if String.trim(name) != "", do: String.trim(name), else: generate_username()
    
    socket = 
      socket
      |> assign(:username, username)
      |> assign(:show_username_form, false)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_username", _params, socket) do
    {:noreply, assign(socket, :show_username_form, false)}
  end

  @impl true
  def handle_event("join_room", %{"room_name" => room_name}, socket) do
    if String.trim(room_name) != "" do
      room = String.trim(room_name) |> String.downcase() |> String.replace(" ", "-")
      {:noreply, push_navigate(socket, to: ~p"/room/#{room}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    # Only add message if it's for the current room
    if message.room == socket.assigns.room do
      messages = [message | socket.assigns.messages]
      {:noreply, assign(socket, :messages, messages)}
    else
      {:noreply, socket}
    end
  end

  defp generate_username do
    adjectives = ["Happy", "Clever", "Bright", "Swift", "Kind", "Bold", "Calm", "Cool"]
    nouns = ["Panda", "Tiger", "Eagle", "Wolf", "Bear", "Fox", "Owl", "Cat"]
    
    adjective = Enum.random(adjectives)
    noun = Enum.random(nouns)
    number = :rand.uniform(999)
    
    "#{adjective}#{noun}#{number}"
  end

  defp format_timestamp(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} ->
        dt
        |> DateTime.shift_zone!("Etc/UTC")
        |> Calendar.strftime("%H:%M")
      _ ->
        "??:??"
    end
  end
end
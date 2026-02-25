defmodule CloudmsgWeb.ChatChannel do
  @moduledoc """
  Phoenix Channel for CloudMsg chat rooms.

  Uses Manifold PubSub for efficient message broadcasting and
  Presence for tracking online users.
  """

  use CloudmsgWeb, :channel

  alias Cloudmsg.{PubSub, Session.Presence}

  @impl true
  def join("chat:" <> room_id, _payload, socket) do
    # Set partitioner key for consistent routing
    user_id = socket.assigns[:user_id] || generate_user_id()
    Cloudmsg.Router.set_partitioner_key(user_id)

    socket =
      socket
      |> assign(:room_id, "chat:" <> room_id)
      |> assign(:user_id, user_id)

    # Send async message to complete join
    send(self(), :after_join)

    {:ok, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    room_id = socket.assigns.room_id
    user_id = socket.assigns.user_id

    # Subscribe to Manifold PubSub
    :ok = PubSub.subscribe(room_id, self())

    # Track presence
    :ok = Presence.track(socket, user_id, %{
      online_at: System.system_time(:second),
      user_id: user_id
    })

    # Get current presence list
    presences = Presence.list(room_id)

    # Push presence list to the joining user
    push(socket, "presence_state", %{presences: presences})

    # Broadcast join event
    broadcast_from!(socket, "user_joined", %{
      user_id: user_id,
      online_at: System.system_time(:second)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:cloudmsg_broadcast, _room_id, message}, socket) do
    push(socket, "new_msg", message)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:presence_diff, diff}, socket) do
    push(socket, "presence_diff", diff)
    {:noreply, socket}
  end

  @impl true
  def handle_in("new_msg", %{"text" => text}, socket) do
    room_id = socket.assigns.room_id
    user_id = socket.assigns.user_id

    message = %{
      user_id: user_id,
      text: sanitize_text(text),
      timestamp: System.system_time(:millisecond)
    }

    # Broadcast using Manifold
    :ok = PubSub.broadcast(room_id, message)

    {:noreply, socket}
  end

  @impl true
  def handle_in("typing", %{"typing" => typing}, socket) do
    # Broadcast typing indicator
    broadcast_from!(socket, "typing", %{
      user_id: socket.assigns.user_id,
      typing: typing
    })

    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    room_id = socket.assigns.room_id
    :ok = PubSub.unsubscribe(room_id, self())
    :ok
  end

  ## Private Functions

  defp generate_user_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp sanitize_text(text) when is_binary(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.trim()
    |> truncate(1000)
  end

  defp sanitize_text(_), do: ""

  defp truncate(text, max_length) when byte_size(text) > max_length do
    String.slice(text, 0, max_length) <> "..."
  end

  defp truncate(text, _), do: text
end

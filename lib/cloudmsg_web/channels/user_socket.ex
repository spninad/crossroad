defmodule CrossroadWeb.UserSocket do
  @moduledoc """
  Phoenix UserSocket for CloudMsg WebSocket connections.

  Supports the chat channel for real-time messaging using
  the Manifold PubSub system.
  """

  use Phoenix.Socket

  # Channels
  channel "chat:*", CrossroadWeb.ChatChannel

  @impl true
  def connect(params, socket, _connect_info) do
    # Generate or use provided user_id
    user_id = params["user_id"] || generate_user_id()

    # Set Manifold partitioner key for consistent routing
    Crossroad.Router.set_partitioner_key(user_id)

    {:ok, assign(socket, :user_id, user_id)}
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"

  defp generate_user_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end

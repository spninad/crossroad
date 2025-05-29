defmodule CloudMsgWeb.ApiController do
  use CloudMsgWeb, :controller

  def index(conn, _params) do
    json(conn, %{message: "CloudMsg API - Distributed message service"})
  end

  def get_messages(conn, _params) do
    messages = CloudMsg.MessageStore.get_messages("general")
    json(conn, messages)
  end

  def get_message(conn, %{"id" => id}) do
    case CloudMsg.MessageStore.get_message(id) do
      nil -> 
        conn
        |> put_status(404)
        |> json(%{error: "Message not found"})
      message -> 
        json(conn, message)
    end
  end

  def create_message(conn, %{"content" => content}) do
    message = %{content: content}
    
    case CloudMsg.MessageStore.add_message("general", message) do
      {:ok, id} ->
        conn
        |> put_status(201)
        |> json(%{id: id, message: "Message created"})
      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{error: reason})
    end
  end

  def create_message(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Invalid request body. Expected {\"content\": \"message\"}"})
  end

  def list_rooms(conn, _params) do
    rooms = CloudMsg.MessageStore.list_rooms()
    json(conn, %{rooms: rooms})
  end

  def get_room_messages(conn, %{"room" => room}) do
    messages = CloudMsg.MessageStore.get_messages(room)
    json(conn, messages)
  end

  def create_room_message(conn, %{"room" => room, "content" => content, "user" => user}) do
    message = %{content: content, user: user}
    
    case CloudMsg.MessageStore.add_message(room, message) do
      {:ok, id} ->
        conn
        |> put_status(201)
        |> json(%{id: id, message: "Message created in room #{room}"})
      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{error: reason})
    end
  end

  def create_room_message(conn, %{"room" => room, "content" => content}) do
    message = %{content: content, user: "Anonymous"}
    
    case CloudMsg.MessageStore.add_message(room, message) do
      {:ok, id} ->
        conn
        |> put_status(201)
        |> json(%{id: id, message: "Message created in room #{room}"})
      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{error: reason})
    end
  end

  def create_room_message(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Invalid request body. Expected {\"content\": \"message\", \"user\": \"username\"}"})
  end
end
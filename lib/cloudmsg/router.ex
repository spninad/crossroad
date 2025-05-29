defmodule CloudMsg.Router do
  use Plug.Router

  plug Plug.Logger
  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  get "/" do
    send_resp(conn, 200, "CloudMsg API - Simple message service")
  end

  get "/messages" do
    messages = CloudMsg.MessageStore.get_messages()
    json_response(conn, 200, messages)
  end

  get "/messages/:id" do
    case CloudMsg.MessageStore.get_message(id) do
      nil -> 
        json_response(conn, 404, %{error: "Message not found"})
      message -> 
        json_response(conn, 200, message)
    end
  end

  post "/messages" do
    case conn.body_params do
      %{"content" => content} when is_binary(content) ->
        message = %{
          content: content,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }
        {:ok, id} = CloudMsg.MessageStore.add_message(message)
        json_response(conn, 201, %{id: id, message: "Message created"})
      
      _ ->
        json_response(conn, 400, %{error: "Invalid request body. Expected {\"content\": \"message\"}"})
    end
  end

  match _ do
    json_response(conn, 404, %{error: "Not found"})
  end

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
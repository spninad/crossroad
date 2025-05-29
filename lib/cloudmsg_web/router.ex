defmodule CloudMsgWeb.Router do
  use CloudMsgWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CloudMsgWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CloudMsgWeb do
    pipe_through :browser

    live "/", ChatLive
    live "/room/:room", ChatLive
  end

  # API routes for backward compatibility
  scope "/api", CloudMsgWeb do
    pipe_through :api

    get "/", ApiController, :index
    get "/messages", ApiController, :get_messages
    get "/messages/:id", ApiController, :get_message
    post "/messages", ApiController, :create_message
    get "/rooms", ApiController, :list_rooms
    get "/rooms/:room/messages", ApiController, :get_room_messages
    post "/rooms/:room/messages", ApiController, :create_room_message
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:cloudmsg, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CloudMsgWeb.Telemetry
    end
  end
end
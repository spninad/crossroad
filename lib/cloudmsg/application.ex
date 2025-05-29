defmodule CloudMsg.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CloudMsgWeb.Telemetry,
      {Registry, keys: :unique, name: CloudMsg.RoomRegistry},
      CloudMsg.RoomSupervisor,
      CloudMsgWeb.Endpoint,
      # Keep the old API for backward compatibility
      {Plug.Cowboy, scheme: :http, plug: CloudMsg.Router, options: [port: 4001]}
    ]

    opts = [strategy: :one_for_one, name: CloudMsg.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    CloudMsgWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
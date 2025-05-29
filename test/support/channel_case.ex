defmodule CloudMsgWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.

  Such tests rely on `Phoenix.ChannelTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox here so that this process shares
  the same sandbox as the test process.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import CloudMsgWeb.ChannelCase

      # The default endpoint for testing
      @endpoint CloudMsgWeb.Endpoint
    end
  end

  setup _tags do
    :ok
  end
end
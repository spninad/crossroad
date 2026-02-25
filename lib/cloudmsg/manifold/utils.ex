defmodule Crossroad.Manifold.Utils do
  @moduledoc """
  Utility functions for the Manifold message broadcasting system.
  Provides fast grouping, partitioning, hashing, and message packing.
  """

  @type groups :: %{any => [pid]}
  @type key_fun :: (any -> any)

  @doc """
  A faster version of Enum.group_by with less bells and whistles.
  Groups pids by the result of the key function.
  """
  @spec group_by([pid], key_fun) :: groups
  def group_by(pids, key_fun), do: group_by(pids, key_fun, %{})

  @spec group_by([pid], key_fun, groups) :: groups
  defp group_by([pid | pids], key_fun, groups) do
    key = key_fun.(pid)
    group = Map.get(groups, key, [])
    group_by(pids, key_fun, Map.put(groups, key, [pid | group]))
  end

  defp group_by([], _key_fun, groups), do: groups

  @doc """
  Partitions a bunch of pids into a tuple of lists of pids
  grouped by the result of :erlang.phash2/2
  """
  @spec partition_pids([pid], integer) :: tuple
  def partition_pids(pids, partitions) do
    do_partition_pids(pids, partitions, Tuple.duplicate([], partitions))
  end

  defp do_partition_pids([pid | pids], partitions, pids_by_partition) do
    partition = partition_for(pid, partitions)
    pids_in_partition = elem(pids_by_partition, partition)

    do_partition_pids(
      pids,
      partitions,
      put_elem(pids_by_partition, partition, [pid | pids_in_partition])
    )
  end

  defp do_partition_pids([], _partitions, pids_by_partition), do: pids_by_partition

  @doc """
  Computes the partition for a given pid using :erlang.phash2/2
  """
  @spec partition_for(pid, integer) :: integer
  def partition_for(pid, partitions) do
    :erlang.phash2(pid, partitions)
  end

  @doc """
  Computes a hash for a given key using MD5.
  Used for consistent routing to partitioners and senders.
  """
  @spec hash(atom | binary | integer) :: integer
  def hash(key) when is_binary(key) do
    <<_::binary-size(8), value::unsigned-little-integer-size(64)>> = :erlang.md5(key)
    value
  end

  def hash(key), do: hash("#{key}")

  @doc """
  Gets the next delay at which we should attempt to hibernate a worker or partitioner process.
  Returns a random delay between hibernate_delay and hibernate_delay + hibernate_jitter.
  """
  @spec next_hibernate_delay() :: integer
  def next_hibernate_delay() do
    hibernate_delay = Application.get_env(:crossroad, :hibernate_delay, 60_000)
    hibernate_jitter = Application.get_env(:crossroad, :hibernate_jitter, 30_000)

    hibernate_delay + :rand.uniform(hibernate_jitter)
  end

  @doc """
  Packs a message based on the pack mode.
  :binary - converts the message to binary using term_to_binary
  :etf or nil - returns the message as-is
  """
  @spec pack_message(atom, term()) :: term()
  def pack_message(:binary, message), do: {:manifold_binary, :erlang.term_to_binary(message)}
  def pack_message(_mode, message), do: message

  @doc """
  Unpacks a message that was packed with pack_message/2.
  """
  @spec unpack_message(term()) :: term()
  def unpack_message({:manifold_binary, binary}), do: :erlang.binary_to_term(binary)
  def unpack_message(message), do: message
end

defmodule BehaviorTree.Node do
  @moduledoc """
  A behavior tree node type.

  Currently only supports "select" and "sequence" style nodes.
  """

  @enforce_keys [:type, :children]
  defstruct [:type, :children]

  @opaque t :: %__MODULE__{type: String.t(), children: list(__MODULE__.t() | any())}

  @doc """
  Create a "select" style node with the supplied children.

  This node always goes from left to right, moving on to the next child when the current one fails.  Succeeds immediately if any child succeeds, fails if all children fail.

  The children can be a mix of other nodes to create deeper trees, or any other value to create a leaf (an atom or function is recommended).

  ## Example

      iex> tree = Node.select([:a, :b])
      iex> tree |> BehaviorTree.start |> BehaviorTree.fail |> BehaviorTree.value
      :b

      iex> tree = Node.select([
      ...>          Node.select([:a, :b]),
      ...>          :c
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.fail |> BehaviorTree.fail |> BehaviorTree.value
      :c

      iex> tree = Node.sequence([
      ...>          Node.select([:a, :b]),
      ...>          :c
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.succeed |> BehaviorTree.value
      :c

  """
  @spec select(list()) :: __MODULE__.t()
  def select(children) when is_list(children) do
    %__MODULE__{type: :select, children: children}
  end

  @doc """
  Create a "sequence" style node with the supplied children.

  This node always goes from left to right, moving on to the next child when the current one succeeds.  Succeeds if all children succeed, fails immediately if any child fails.

  The children can be a mix of other nodes to create deeper trees, or any other value to create a leaf (an atom or function is recommended).

  ## Example

      iex> tree = Node.sequence([:a, :b])
      iex> tree |> BehaviorTree.start |> BehaviorTree.succeed |> BehaviorTree.value
      :b

      iex> tree = Node.sequence([
      ...>          Node.sequence([:a, :b]),
      ...>          :c
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.succeed |> BehaviorTree.succeed |> BehaviorTree.value
      :c

      iex> tree = Node.select([
      ...>          Node.sequence([:a, :b]),
      ...>          :c
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.fail |> BehaviorTree.value
      :c
  """
  @spec sequence(list()) :: __MODULE__.t()
  def sequence(children) when is_list(children) do
    %__MODULE__{type: :sequence, children: children}
  end
end

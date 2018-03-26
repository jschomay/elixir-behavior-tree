defprotocol BehaviorTree.Node.Protocol do
  @moduledoc """
  A protocol so you can define your own custom behavior tree nodes.

  If you would like to make your own nodes with custom traversal behavior, you need to implement this protocol.  A node is just a wrapper around a collection of children, that defines a context on how to traverse the tree when one of its children fails or succeeds. 

  Note that any node that has _not_ explicitly implemented this protocol will be considered a leaf.
  
  `BehaviorTree` is backed by `ExZipper.Zipper`, so you will need to understand how that library works.

  Each function will provide your node as the first argument as per the protocol standard, but many will also include the current zipper as the second argument.

  For examples, look at the source of the standard `BehaviorTree.Node`s.
  """

  @fallback_to_any true

  @doc "Sets the node's children."
  @spec set_children(any(), list(any())) :: any()
  def set_children(data, children)

  @doc "Get the node's children."
  @spec get_children(any()) :: list(any())
  def get_children(data)

  @doc """
  Focus your node's first child.

  In most cases, this will be the first (left-most) child, but in some cases, like for a "random" node, it could be a different child.

  The supplied zipper will be focused on your node, and you need to advance it to the starting child.  Usually `ExZipper.Zipper.down/1` would be desired.
  """
  @spec first_child(any(), Zipper.t()) :: Zipper.t()
  def first_child(data, zipper)

  @doc """
  What to do when one of your node's children fail.

  This is the meat of your custom node logic.  You can move the zipper's focus to a different child (usually with `ExZipper.Zipper.next/1`), or signal that your entire node failed by returning the special atom `:fail`.  
  
  Note that you will need to handle any of the `t:ExZipper.Zipper.error/0` types (like `:right_from_rightmost`) appropriately.
  """
  @spec on_fail(any(), Zipper.t()) :: Zipper.t() | :fail
  def on_fail(data, zipper)

  @doc """
  What to do when one of your node's children succeeds.

  This is the meat of your custom node logic.  You can move the zipper's focus to a different child (usually with `ExZipper.Zipper.next/1`), or signal that your entire node succeeded by returning the special atom `:succeed`.  
  
  Note that you will need to handle any of the `t:ExZipper.Zipper.error/0` types (like `:right_from_rightmost`) appropriately.
  """
  @spec on_succeed(any(), Zipper.t()) :: Zipper.t() | :succeed
  def on_succeed(data, zipper)
end

defimpl BehaviorTree.Node.Protocol, for: Any do
  def set_children(data, _children), do: data
  def get_children(_data), do: []
  def first_child(_data, zipper), do: zipper
  def on_fail(_data, zipper), do: zipper
  def on_succeed(_data, zipper), do: zipper
end

defmodule BehaviorTree.Node do
  @moduledoc """
  A collection of "standard" behavior tree nodes (`select`, `sequence`).

  These nodes implement `BehaviorTree.Node.Protocol`.
  """
  alias ExZipper.Zipper

  defstruct [:type, :children]
  @opaque t :: %__MODULE__{type: String.t(), children: list(any())}

  defimpl BehaviorTree.Node.Protocol do
    def set_children(%BehaviorTree.Node{} = data, children) do
      %BehaviorTree.Node{data | children: children}
    end

    def get_children(%BehaviorTree.Node{children: children}), do: children

    def first_child(_data, zipper), do: Zipper.down(zipper)

    def on_succeed(%BehaviorTree.Node{type: :select}, _zipper), do: :succeed

    def on_succeed(%BehaviorTree.Node{type: :sequence}, zipper) do
      case Zipper.right(zipper) do
        {:error, :right_from_rightmost} ->
          :succeed

        next ->
          next
      end
    end

    def on_fail(%BehaviorTree.Node{type: :sequence} = _data, _zipper) do
      :fail
    end

    def on_fail(%BehaviorTree.Node{type: :select} = _data, zipper) do
      case Zipper.right(zipper) do
        {:error, :right_from_rightmost} ->
          :fail

        next ->
          next
      end
    end
  end

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
  @spec select(nonempty_list()) :: __MODULE__.t()
  def select(children) when is_list(children) and length(children) != 0 do
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
  @spec sequence(nonempty_list()) :: __MODULE__.t()
  def sequence(children) when is_list(children) and length(children) != 0 do
    %__MODULE__{type: :sequence, children: children}
  end
end

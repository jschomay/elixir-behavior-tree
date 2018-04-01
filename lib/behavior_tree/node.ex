defprotocol BehaviorTree.Node.Protocol do
  @moduledoc """
  A protocol so you can define your own custom behavior tree nodes.

  If you would like to make your own nodes with custom traversal behavior, you need to implement this protocol.  A node is just a wrapper around a collection of children, that defines a context on how to traverse the tree when one of its children fails or succeeds. 

  Note that any node that has _not_ explicitly implemented this protocol will be considered a leaf.

  `BehaviorTree` is backed by `ExZipper.Zipper`, so you will need to understand how that library works.

  Each function will provide your node as the first argument as per the protocol standard, but many will also include the current zipper as the second argument.

  For examples, look at the source of the standard `BehaviorTree.Node`s.

  Note that your nodes can be stateful if necessary, see the implementation for `BehaviorTree.Node.repeat_n/2` for an example.
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

  This is the meat of your custom node logic.  You can move the zipper's focus to a different child (usually with `ExZipper.Zipper.right/1`), or signal that your entire node failed or succeeded by returning the special atom `:fail` or `:succeed`.  

  Note that you will need to handle any of the `t:ExZipper.Zipper.error/0` types (like `:right_from_rightmost`) appropriately.
  """
  @spec on_fail(any(), Zipper.t()) :: Zipper.t() | :succeed | :fail
  def on_fail(data, zipper)

  @doc """
  What to do when one of your node's children succeeds.

  This is the meat of your custom node logic.  You can move the zipper's focus to a different child (usually with `ExZipper.Zipper.right/1`), or signal that your entire node failed or succeeded by returning the special atom `:fail` or `:succeed`.

  Note that you will need to handle any of the `t:ExZipper.Zipper.error/0` types (like `:right_from_rightmost`) appropriately.
  """
  @spec on_succeed(any(), Zipper.t()) :: Zipper.t() | :succeed | :fail
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
  A collection of "standard" behavior tree nodes.

  By composing these nodes, you should be able to describe almost any behavior you need.  The children of each node can be a mix of other nodes to create deeper trees, or any other value to create a leaf (an atom or function is recommended).

  These nodes implement `BehaviorTree.Node.Protocol`.
  """
  alias ExZipper.Zipper

  defstruct [:type, :children, :repeat_count]
  @opaque t :: %__MODULE__{type: String.t(), children: list(any()), repeat_count: pos_integer()}

  defimpl BehaviorTree.Node.Protocol do
    def set_children(%BehaviorTree.Node{} = data, children) do
      %BehaviorTree.Node{data | children: children}
    end

    def get_children(%BehaviorTree.Node{children: children}), do: children

    def first_child(%BehaviorTree.Node{type: :random, children: children}, zipper) do
      random_index = :rand.uniform(Enum.count(children)) - 1
      n_times = [nil] |> Stream.cycle() |> Enum.take(random_index)
      zipper
      |> Zipper.down()
      |> (fn zipper -> Enum.reduce(n_times, zipper, fn _, z -> Zipper.right(z) end) end).()
    end

    def first_child(_data, zipper), do: Zipper.down(zipper)

    def on_succeed(%BehaviorTree.Node{type: type, repeat_count: repeat_count}, zipper) do
      case type do
        :sequence ->
          case Zipper.right(zipper) do
            {:error, :right_from_rightmost} ->
              :succeed

            next ->
              next
          end

        :select ->
          :succeed

        :repeat_until_fail ->
          zipper

        :repeat_until_succeed ->
          :succeed

        :repeat_n ->
          if repeat_count > 1 do
            zipper
            |> Zipper.up()
            |> Zipper.edit(&%BehaviorTree.Node{&1 | repeat_count: repeat_count - 1})
            |> Zipper.down()
          else
            :succeed
          end

        :random ->
          :succeed
      end
    end

    def on_fail(%BehaviorTree.Node{type: type, repeat_count: repeat_count}, zipper) do
      case type do
        :sequence ->
          :fail

        :select ->
          case Zipper.right(zipper) do
            {:error, :right_from_rightmost} ->
              :fail

            next ->
              next
          end

        :repeat_until_fail ->
          :succeed

        :repeat_until_succeed ->
          zipper

        :repeat_n ->
          if repeat_count > 1 do
            zipper
            |> Zipper.up()
            |> Zipper.edit(&%BehaviorTree.Node{&1 | repeat_count: repeat_count - 1})
            |> Zipper.down()
          else
            :succeed
          end

        :random ->
          :fail
      end
    end
  end

  @doc """
  Create a "select" style node with the supplied children.

  This node always goes from left to right, moving on to the next child when the current one fails.  Succeeds immediately if any child succeeds, fails if all children fail.

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

  @doc """
  Create a "repeat_until_fail" style "decorator" node.

  This node only takes a single child, which it will repeatedly return until the child fails, at which point this node will succeed.  This node never fails, but it may run forever if the child never fails.

  You may find it useful to nest one of the other nodes under this node if you want a collection of children to repeat.

  ## Example

      iex> tree = Node.sequence([
      ...>          Node.repeat_until_fail(:a),
      ...>          :b
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.succeed |> BehaviorTree.succeed |> BehaviorTree.value
      :a

      iex> tree = Node.sequence([
      ...>          Node.repeat_until_fail(:a),
      ...>          :b
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.succeed |> BehaviorTree.fail |> BehaviorTree.value
      :b

      iex> tree = Node.sequence([
      ...>          Node.repeat_until_fail(Node.select([:a, :b])),
      ...>          :c
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.fail |> BehaviorTree.fail |> BehaviorTree.value
      :c
  """
  @spec repeat_until_fail(any()) :: __MODULE__.t()
  def repeat_until_fail(child) do
    %__MODULE__{type: :repeat_until_fail, children: [child]}
  end

  @doc """
  Create a "repeat_until_succeed" style "decorator" node.

  This node only takes a single child, which it will repeatedly return until the child succeeds, at which point this node will succeed.  This node never fails, but it may run forever if the child never succeeds.

  You may find it useful to nest one of the other nodes under this node if you want a collection of children to repeat.

  ## Example

      iex> tree = Node.sequence([
      ...>          Node.repeat_until_succeed(:a),
      ...>          :b
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.fail |> BehaviorTree.fail |> BehaviorTree.value
      :a

      iex> tree = Node.sequence([
      ...>          Node.repeat_until_succeed(:a),
      ...>          :b
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.fail |> BehaviorTree.succeed |> BehaviorTree.value
      :b

      iex> tree = Node.sequence([
      ...>          Node.repeat_until_succeed(Node.sequence([:a, :b])),
      ...>          :c
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.succeed |> BehaviorTree.succeed |> BehaviorTree.value
      :c
  """
  @spec repeat_until_succeed(any()) :: __MODULE__.t()
  def repeat_until_succeed(child) do
    %__MODULE__{type: :repeat_until_succeed, children: [child]}
  end

  @doc """
  Create a "repeat_n" style "decorator" node.

  This node takes an integer greater than 1, and a single child, which it will repeatedly return n times, regardless of if the child fails or succeeds.  After that, this node will succeed.  This node never fails, and always runs n times.

  You may find it useful to nest one of the other nodes under this node if you want a collection of children to repeat.

  ## Example

      iex> tree = Node.sequence([
      ...>          Node.repeat_n(2, :a),
      ...>          :b
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.value
      :a
      iex> tree |> BehaviorTree.start |> BehaviorTree.fail |> BehaviorTree.value
      :a
      iex> tree |> BehaviorTree.start |> BehaviorTree.fail |> BehaviorTree.fail |> BehaviorTree.value
      :b
  """
  @spec repeat_n(pos_integer, any()) :: __MODULE__.t()
  def repeat_n(n, child) when n > 1 do
    %__MODULE__{type: :repeat_n, children: [child], repeat_count: n}
  end

  @doc """
  Create a "random" style "decorator" node.

  This node takes multiple children, from which it will randomly pick one to run (using `:rand.uniform/1`).  If that child fails, this node fails, if the child succeeds, this node succeeds.

  ## Example

      Node.random([:a, :b, :c]) |> BehaviorTree.start |> BehaviorTree.value # will be one of :a, :b, or :c

      iex> tree = Node.sequence([
      ...>          Node.random([:a, :b, :c]),
      ...>          :d
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.succeed |> BehaviorTree.value
      :d
  """
  @spec random(nonempty_list()) :: __MODULE__.t()
  def random(children) when is_list(children) and length(children) != 0 do
    %__MODULE__{type: :random, children: children}
  end
end

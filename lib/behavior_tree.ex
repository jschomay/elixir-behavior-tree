defmodule BTNode do
  @moduledoc """
  A behavior tree node type.

  Currently only supports "select" and "sequence" style nodes.
  """

  @enforce_keys [:type, :children]
  defstruct [:type, :children]

  @opaque t :: %__MODULE__{type: String.t(), children: list(BTNode.t() | any())}
end

defmodule BehaviorTree do
  @moduledoc """
  A library for building [behavior trees](https://en.wikipedia.org/wiki/Behavior_tree_(artificial_intelligence,_robotics_and_control)).

  ### About

  A behavior tree is a method for encapsulating complex, nested logic in a declarative data structure.  They are often used for video games and AI.

  The key mechanics of a behavior tree is that _inner_ nodes describe how to traverse the tree, and _leaf_ nodes are the actual values or "behaviors."  A behavior tree always has a value of one of its leaf nodes, which is advanced by signalling that the current behavior should "succeed" or "fail."

  #### Nodes

  The primary inner nodes that make up a behavior tree are "select" and "sequence" nodes:

  _Select_ nodes will go through their children from left to right.  If a child fails, it moves on to the next one.  If the last one fails, the select node fails.  As soon as any child succeeds, the select node succeeds (and stops traversing its children).

  _Sequence_ nodes also go through their children from left to right.  If a child fails, the whole select node fails (and stop traversing its children).  If a child succeeds, it moves on to the next child.  If the last one succeeds, the select node succeeds.

  By composing these nodes as needed, you can build up complex behaviors in a simple data structure.  There are also be other types of inner nodes (like randomly choosing from its children), and "decorator" nodes, which modify a single child (like repeating it n times).  Also, in this implementation, the whole tree will "start over" after exhausting all of its nodes.

  #### Behavior trees vs decision trees and state machines

  Behavior trees are similar to decision trees and state machines, but have important differences.  Where a decision tree "drills down" from general to specific to reach a leaf, behavior trees are stateful, and move from leaf to leaf over time based on their current context.  In that way, behavior trees are more like state machines, but they differ by leveraging the simplicity and power of composable trees to create more complex transition logic.

  ### Example

  Let's build an AI to play [Battleship](https://en.wikipedia.org/wiki/Battleship_(game)).

  The rules are simple: "ships" are secretly arranged on a 2D grid, and players guess coordinates, trying to "sink" all of the ships, by getting the clues "hit", "miss", and "sunk" after each guess.

  The playing strategy is fairly simple, but we will make a few iterations of our AI.

  > Note, This example splits up the code into two parts: 1) the tree itself, which only expresses what it wants to do at any given step, and 2) the "handler" code, which interprets the tree's intent, does the appropriate work, and updates the tree with the outcome.  An alternative approach would be to load the tree's leafs with functions that could be called directly.

  #### AI "A" - random guessing

  This AI doesn't really have a strategy, and doesn't require a behavior tree, but it is a place to start.

      ai_a = BT.sequence([:random_guess])

  Every play, calling `BT.value` will return `:random_guess`.  Responding to that "behavior" with either `BT.fail` or `BT.succeed` will not change what we get next time around.

  Note that the root of the tree will "start over" if it fails or succeeds, which is what keeps it running even after traversing all of the nodes.

  Also note that the behavior tree does not actually know how to make a random guess, or what a valid random guess is, it just declares its _intent_, allowing the "handler" code to turn that intent into a guess, and then give appropriate feedback.

  #### AI "B" - brute force

  We can encode a brute force strategy as a tree:

      row_by_row =
        BT.continually(
          BT.select([
            :go_right,
            :beginning_of_next_row
          ])
        )

      ai_b =
        BT.sequence([
          :top_left,
          row_by_row
        ])

  "B" is notably more complex, making use of three different inner nodes.  `BT.continually` will repeat its one child node until it fails (in this case, it will only fail after all of the board has been guessed).  Note that "B" depends on the handler code to keep track of its last guess, but it always requests a single, discrete next guess.  Each time `:go_right` succeeds, the `select` node will succeed, and the `continually` node will restart it.  If `go_right` goes off the board (aka "fails"), the `select` node will move on to `:beginning_of_next_row`, which the handling code will succeed, which will "bubble up" to the `select` and `continually` nodes, restarting again at `:go_right` for the next call.

  Note that any time the value of the tree fails, the handler code won't have a valid coordinate, requiring an additional "tick" through the tree in order to get a valid guess.

  #### AI "C" - zero in

  AI "C" is the smartest of the bunch, randomly guessing until getting a "hit", and then scanning left, right, up, or down appropriately until getting a "sunk."

      search_horizontally =
        BT.select([
          :go_right,
          :go_left
        ])

      search_vertically =
        BT.select([
          :go_up,
          :go_down
        ])

      narrow_down =
        BT.select([
          search_horizontally,
          search_vertically
        ])

      ai_c =
        BT.sequence([
          :random_guess,
          narrow_down
        ])

  "C" is quite complex, and requires specific feedback from the handler code.  When randomly guessing, a "miss" should get a `BT.fail`, a "hit" should get a `BT.succeed`, and a "sunk" should not update the tree at all, so that it will still be making random guesses next time (note that `BT.fail` would work the same in this case, but is less clear).

  When narrowing down, a "hit" should leave the tree as it is for next time, a "miss" should get a `BT.fail`, and a "sunk" should get a `BT.success`.  In the case that a guess is invalid (goes off the board), it should respond with a `BT.fail` and run it again.
  """
  alias ExZipper.Zipper

  defstruct [:zipper]

  @opaque t :: %__MODULE__{zipper: Zipper.t()}

  @doc """
  Start your behavior tree.  

  Note that the input is a static, declarative data structure, while the output is stateful, and will always have a value of one of the leafs.

  The initial value will be the leaf reached from following a descent through each node (for a tree of selects and sequences this will be the deepest left-most leaf, but other types of nodes may have different initiation behaviors).

  ## Example

      iex> tree = BehaviorTree.sequence([
      ...>          BehaviorTree.sequence([:a, :b, :c]),
      ...>          BehaviorTree.select([:x, :y, :z]),
      ...>          :done
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.value
      :a

  """
  @spec start(BTNode.t()) :: __MODULE__.t()
  def start(node = %BTNode{}) do
    Zipper.zipper(
      fn
        %BTNode{} -> true
        _leaf -> false
      end,
      fn %BTNode{children: children} -> children end,
      fn
        %BTNode{} = node, children -> %BTNode{node | children: children}
        _node, children -> %BTNode{type: :select, children: children}
      end,
      node
    )
    |> descend_to_leaf
    |> (fn zipper -> %__MODULE__{zipper: zipper} end).()
  end

  @doc """
  Triggers the tree to advance to the next state.

  The active leaf node will trigger its parent to succeed.  The specifics of how the parent will traverse next, depend on the type of node that it is; see the documentation for specific node types.
  """
  @spec succeed(__MODULE__.t()) :: __MODULE__.t()
  def succeed(bt = %__MODULE__{}) do
    new_focus = succeed_(bt.zipper)
    %{bt | zipper: new_focus}
  end

  @spec succeed_(Zipper.t()) :: Zipper.t()
  defp succeed_(zipper) do
    if Zipper.root(zipper) == zipper do
      descend_to_leaf(zipper)
    else
      parent = Zipper.up(zipper)

      case Zipper.node(parent) do
        %BTNode{type: :sequence} ->
          case Zipper.right(zipper) do
            {:error, :right_from_rightmost} ->
              succeed_(parent)

            next ->
              descend_to_leaf(next)
          end

        %BTNode{type: :select} ->
          succeed_(parent)
      end
    end
  end

  @doc """
  Triggers the tree to advance to the next state.

  The active leaf node will trigger its parent to fail.  The specifics of how the parent will traverse next, depend on the type of node that it is; see the documentation for specific node types.
  """
  @spec fail(__MODULE__.t()) :: __MODULE__.t()
  def fail(bt = %__MODULE__{}) do
    new_focus = fail_(bt.zipper)
    %{bt | zipper: new_focus}
  end

  @spec fail_(Zipper.t()) :: Zipper.t()
  defp fail_(zipper) do
    if Zipper.root(zipper) == zipper do
      descend_to_leaf(zipper)
    else
      parent = Zipper.up(zipper)

      case Zipper.node(parent) do
        %BTNode{type: :sequence} ->
          fail_(parent)

        %BTNode{type: :select} ->
          case Zipper.right(zipper) do
            {:error, :right_from_rightmost} ->
              fail_(parent)

            next ->
              descend_to_leaf(next)
          end
      end
    end
  end

  @doc """
  Get the current "behavior"

  This will always be one of the leaf nodes, based on the current state of the tree.
  """
  @spec value(__MODULE__.t()) :: any()
  def value(bt = %__MODULE__{}) do
    Zipper.node(bt.zipper)
  end

  @spec descend_to_leaf(Zipper.t()) :: Zipper.t()
  defp descend_to_leaf(zipper) do
    case Zipper.node(zipper) do
      %BTNode{} ->
        zipper
        |> Zipper.down()
        |> descend_to_leaf

      _leaf ->
        zipper
    end
  end

  @doc """
  Create a "select" style node with the supplied children.

  This node always goes from left to right, moving on to the next child when the current one fails.  Succeeds immediately if any child succeeds, fails if all children fail.

  The children can be a mix of other nodes to create deeper trees, or any other value to create a leaf (an atom or function is recommended).

  ## Example

      iex> tree = BehaviorTree.select([:a, :b])
      iex> tree |> BehaviorTree.start |> BehaviorTree.fail |> BehaviorTree.value
      :b

      iex> tree = BehaviorTree.select([
      ...>          BehaviorTree.select([:a, :b]),
      ...>          :c
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.fail |> BehaviorTree.fail |> BehaviorTree.value
      :c

      iex> tree = BehaviorTree.sequence([
      ...>          BehaviorTree.select([:a, :b]),
      ...>          :c
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.succeed |> BehaviorTree.value
      :c

  """
  @spec select(list()) :: BTNode.t()
  def select(children) when is_list(children) do
    %BTNode{type: :select, children: children}
  end

  @doc """
  Create a "sequence" style node with the supplied children.

  This node always goes from left to right, moving on to the next child when the current one succeeds.  Succeeds if all children succeed, fails immediately if any child fails.

  The children can be a mix of other nodes to create deeper trees, or any other value to create a leaf (an atom or function is recommended).

  ## Example

      iex> tree = BehaviorTree.sequence([:a, :b])
      iex> tree |> BehaviorTree.start |> BehaviorTree.succeed |> BehaviorTree.value
      :b

      iex> tree = BehaviorTree.sequence([
      ...>          BehaviorTree.sequence([:a, :b]),
      ...>          :c
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.succeed |> BehaviorTree.succeed |> BehaviorTree.value
      :c

      iex> tree = BehaviorTree.select([
      ...>          BehaviorTree.sequence([:a, :b]),
      ...>          :c
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.fail |> BehaviorTree.value
      :c
  """
  @spec sequence(list()) :: BTNode.t()
  def sequence(children) when is_list(children) do
    %BTNode{type: :sequence, children: children}
  end
end

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

  (You can jump directly to the [fully implemented AI code](https://github.com/jschomay/elixir-battleship-guesser/blob/master/lib/ai.ex)).

  #### AI "A" - random guessing

  This AI doesn't really have a strategy, and doesn't require a behavior tree, but it is a place to start.

      ai_a = Node.sequence([:random_guess])

  Every play, calling `BehaviorTree.value` will return `:random_guess`.  Responding to that "behavior" with either `BehaviorTree.fail` or `BehaviorTree.succeed` will not change what we get next time around.

  Note that the root of the tree will "start over" if it fails or succeeds, which is what keeps it running even after traversing all of the nodes.

  Also note that the behavior tree does not actually know how to make a random guess, or what a valid random guess is, it just declares its _intent_, allowing the "handler" code to turn that intent into a guess, and then give appropriate feedback.

  #### AI "B" - brute force

  We can encode a brute force strategy as a tree:

      row_by_row =
        Node.repeat_until_fail(
          Node.select([
            :go_right,
            :beginning_of_next_row
          ])
        )

      ai_b =
        Node.sequence([
          :top_left,
          row_by_row
        ])

        "B" is notably more complex, making use of three different inner nodes.  `Node.repeat_until_fail` will repeat its one child node until it fails (in this case, it will only fail after `:beginning_of_next_row` fails, which would happen after all of the board has been guessed).  Each time `:go_right` succeeds, the `select` node will succeed, and the `repeat_until_fail` node will restart it.  If `go_right` goes off the board, the handler code will fail it, and the `select` node will move on to `:beginning_of_next_row`, which the handling code will succeed, which will "bubble up" to the `select` and `repeat_until_fail` nodes, restarting again at `:go_right` for the next call.

  Note that any time the value of the tree fails, the handler code won't have a valid coordinate, requiring an additional "tick" through the tree in order to get a valid guess.

  #### AI "C" - zero in

  AI "C" is the smartest of the bunch, randomly guessing until getting a "hit", and then scanning left, right, up, or down appropriately until getting a "sunk."

      search_horizontally =
        Node.select([
          :go_right,
          :go_left
        ])

      search_vertically =
        Node.select([
          :go_up,
          :go_down
        ])

      narrow_down =
        Node.select([
          search_horizontally,
          search_vertically
        ])

      ai_c =
        Node.sequence([
          :random_guess,
          narrow_down
        ])

  "C" is quite complex, and requires specific feedback from the handler code.  When randomly guessing, a "miss" should get a `BehaviorTree.fail`, a "hit" should get a `BehaviorTree.succeed`, and a "sunk" should not update the tree at all, so that it will still be making random guesses next time (note that `BehaviorTree.fail` would work the same in this case, but is less clear).

  When narrowing down, a "hit" should leave the tree as it is for next time, a "miss" should get a `BehaviorTree.fail`, and a "sunk" should get a `BehaviorTree.success`.  In the case that a guess is invalid (goes off the board), it should respond with a `BehaviorTree.fail` and run it again.
  """
  alias ExZipper.Zipper
  alias BehaviorTree.Node

  defstruct [:zipper]

  @opaque t :: %__MODULE__{zipper: Zipper.t()}

  @doc """
  Start your behavior tree.  

  Note that the input is a static, declarative data structure, while the output is stateful, and will always have a value of one of the leafs.

  The initial value will be the leaf reached from following a descent through each node (for a tree of selects and sequences this will be the deepest left-most leaf, but other types of nodes may have different initiation behaviors).

  Note that the supplied argument should be a structure built from Nodes.  You can use the included standard `BehaviorTree.Node`s, or one of your own that implements `BehaviorTree.Node.Protocol`.  Any other value will be treated as a leaf, which would be a pointless behavior tree.

  ## Example

      iex> tree = Node.sequence([
      ...>          Node.sequence([:a, :b, :c]),
      ...>          Node.select([:x, :y, :z]),
      ...>          :done
      ...>        ])
      iex> tree |> BehaviorTree.start |> BehaviorTree.value
      :a

  """
  @spec start(any) :: __MODULE__.t()
  def start(node) do
    Zipper.zipper(
      fn node -> Node.Protocol.get_children(node) != [] end,
      fn node -> Node.Protocol.get_children(node) end,
      fn node, children -> Node.Protocol.set_children(node, children) end,
      node
    )
    |> descend_to_leaf
    |> (fn zipper -> %__MODULE__{zipper: zipper} end).()
  end

  @doc """
  Signals that the current behavior has "succeeded."  The tree will advance to the next state.

  The specifics on how the tree will advance depend on type of node that the succeeded behavior is under.  See the specific node documentation for the traversal logic.
  """
  @spec succeed(__MODULE__.t()) :: __MODULE__.t()
  def succeed(%__MODULE__{zipper: zipper} = bt) do
    if Zipper.root(zipper) == zipper do
      zipper
      |> descend_to_leaf
      |> (fn zipper -> %__MODULE__{zipper: zipper} end).()
    else
      parent = Zipper.up(zipper)

      case Node.Protocol.on_succeed(Zipper.node(parent), zipper) do
        :succeed ->
          %__MODULE__{bt | zipper: parent} |> succeed

        :fail ->
          %__MODULE__{bt | zipper: parent} |> fail

        %Zipper{} = new_zipper ->
          new_zipper
          |> descend_to_leaf
          |> (fn zipper -> %__MODULE__{zipper: zipper} end).()
      end
    end
  end

  @doc """
  Signals that the current behavior has "failed."  The tree will advance to the next state.

  The specifics on how the tree will advance depend on type of node that the failed behavior is under.  See the specific node documentation for the traversal logic.
  """
  @spec fail(__MODULE__.t()) :: __MODULE__.t()
  def fail(%__MODULE__{zipper: zipper} = bt) do
    if Zipper.root(zipper) == zipper do
      zipper
      |> descend_to_leaf
      |> (fn zipper -> %__MODULE__{zipper: zipper} end).()
    else
      parent = Zipper.up(zipper)

      case Node.Protocol.on_fail(Zipper.node(parent), zipper) do
        :fail ->
          %__MODULE__{bt | zipper: parent} |> fail

        :succeed ->
          %__MODULE__{bt | zipper: parent} |> succeed

        %Zipper{} = new_zipper ->
          new_zipper
          |> descend_to_leaf
          |> (fn zipper -> %__MODULE__{zipper: zipper} end).()
      end
    end
  end

  @doc """
  Get the current "behavior"

  This will always be one of the leaf nodes, based on the current state of the tree.
  """
  @spec value(__MODULE__.t()) :: any()
  def value(%__MODULE__{} = bt) do
    Zipper.node(bt.zipper)
  end

  @spec descend_to_leaf(Zipper.t()) :: Zipper.t()
  defp descend_to_leaf(zipper) do
    case Node.Protocol.first_child(Zipper.node(zipper), zipper) do
      ^zipper ->
        zipper

      %Zipper{} = zipper ->
        descend_to_leaf(zipper)
    end
  end
end

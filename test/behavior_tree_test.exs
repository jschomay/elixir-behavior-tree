defmodule BehaviorTreeTest do
  use ExUnit.Case
  alias BehaviorTree, as: BT
  alias BehaviorTree.Node

  doctest BehaviorTree
  doctest Node

  setup do
    tree =
      Node.sequence([
        Node.sequence([:a, :b, :c]),
        Node.select([:x, :y, Node.select([:z])]),
        :done
      ])

    bt = BT.start(tree)

    {:ok, %{bt: bt}}
  end

  describe "nodes" do
    test "don't take empty lists" do
      assert catch_error(Node.sequence([]))
      assert catch_error(Node.select([]))
    end
  end

  describe "starts over when reaching the end" do
    test "from succeed" do
      tree = Node.select([:a, :b])
      tree = tree |> BT.start() |> BT.succeed() |> BT.succeed()
      assert BT.value(tree) == :a
    end

    test "from fail" do
      tree = Node.sequence([:a, :b])
      tree = tree |> BT.start() |> BT.fail() |> BT.fail()
      assert BT.value(tree) == :a
    end
  end

  test "deep tree example", context do
    assert BT.value(context.bt) == :a

    bt =
      context.bt
      |> BT.succeed()
      |> BT.succeed()
      |> BT.succeed()
      |> BT.fail()
      |> BT.fail()
      |> BT.succeed()

    assert BT.value(bt) == :done
  end

  test "repeat_n for success branch (not done in doctests)" do
    tree =
      Node.sequence([
        Node.repeat_n(2, :a),
        :b
      ])

    assert tree |> BehaviorTree.start() |> BehaviorTree.value() == :a
    assert tree |> BehaviorTree.start() |> BehaviorTree.succeed() |> BehaviorTree.value() == :a

    assert tree |> BehaviorTree.start() |> BehaviorTree.succeed() |> BehaviorTree.succeed()
           |> BehaviorTree.value() == :b
  end

  # TODO `randomly_weighted`
  # TODO run dialyzer
  # TODO update changelog, bump and release
end

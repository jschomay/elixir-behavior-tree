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

  describe "start/1" do
    test "requires a valid Node" do
      assert catch_error(BT.start([:a, :b, :c])) == :function_clause
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
end

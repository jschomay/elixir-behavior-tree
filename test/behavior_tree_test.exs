defmodule BehaviorTreeTest do
  use ExUnit.Case
  alias BehaviorTree, as: BT

  doctest BehaviorTree

  setup do
    tree =
      BT.sequence([
        BT.sequence([:a, :b, :c]),
        BT.select([:x, :y, BT.select([:z])]),
        :done
      ])

    bt = BT.start(tree)

    {:ok, %{bt: bt}}
  end

  describe "start/1" do
    test "requires a valid Node" do
      assert catch_error(BT.start([:a, :b, :c])) == :function_clause
    end

    test "starts over when reaching the end" do
      tree = BT.select([:a, :b])
      tree = tree |> BT.start() |> BT.succeed() |> BT.succeed()
      assert BT.value(tree) == :a
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
end

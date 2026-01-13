defmodule LiveSchema.EmbedsTest do
  use ExUnit.Case, async: true

  defmodule StateWithEmbeds do
    use LiveSchema

    schema do
      field :title, :string, default: ""

      embeds_one :filter do
        field :status, {:enum, [:all, :active, :archived]}, default: :all
        field :search, :string, default: ""
      end

      embeds_many :tags do
        field :name, :string
        field :color, :string, default: "#000000"
      end
    end

    reducer :set_filter_status, [:status] do
      set_filter(state, %{state.filter | status: status})
    end
  end

  describe "embeds_one" do
    test "creates nested struct" do
      state = StateWithEmbeds.new!()

      assert state.filter.__struct__ == StateWithEmbeds.Filter
      assert state.filter.status == :all
      assert state.filter.search == ""
    end

    test "can update nested struct" do
      state = StateWithEmbeds.new!()
      state = StateWithEmbeds.apply(state, {:set_filter_status, :active})

      assert state.filter.status == :active
    end
  end

  describe "embeds_many" do
    test "defaults to empty list" do
      state = StateWithEmbeds.new!()

      assert state.tags == []
    end

    test "introspection includes embeds" do
      embeds = StateWithEmbeds.__live_schema__(:embeds)

      assert :filter in embeds
      assert :tags in embeds
    end
  end
end

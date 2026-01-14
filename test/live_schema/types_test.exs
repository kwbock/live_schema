defmodule LiveSchema.TypesTest do
  use ExUnit.Case, async: true
  doctest LiveSchema.Types

  alias LiveSchema.Types

  defmodule TestStruct do
    defstruct [:field]
  end

  describe "validate_type/2 with primitives" do
    test "validates strings" do
      assert Types.validate_type("hello", :string) == :ok
      assert {:error, _} = Types.validate_type(123, :string)
    end

    test "validates integers" do
      assert Types.validate_type(42, :integer) == :ok
      assert {:error, _} = Types.validate_type("42", :integer)
    end

    test "validates floats" do
      assert Types.validate_type(3.14, :float) == :ok
      assert {:error, _} = Types.validate_type(3, :float)
    end

    test "validates booleans" do
      assert Types.validate_type(true, :boolean) == :ok
      assert Types.validate_type(false, :boolean) == :ok
      assert {:error, _} = Types.validate_type("true", :boolean)
    end

    test "validates atoms" do
      assert Types.validate_type(:hello, :atom) == :ok
      assert {:error, _} = Types.validate_type("hello", :atom)
    end

    test ":any accepts anything" do
      assert Types.validate_type("hello", :any) == :ok
      assert Types.validate_type(123, :any) == :ok
      assert Types.validate_type(nil, :any) == :ok
    end
  end

  describe "validate_type/2 with parameterized types" do
    test "validates lists" do
      assert Types.validate_type([1, 2, 3], {:list, :integer}) == :ok
      assert Types.validate_type([], {:list, :integer}) == :ok
      assert {:error, _} = Types.validate_type([1, "two"], {:list, :integer})
    end

    test "validates enums" do
      assert Types.validate_type(:active, {:enum, [:pending, :active, :done]}) == :ok
      assert {:error, _} = Types.validate_type(:invalid, {:enum, [:pending, :active]})
    end

    test "validates structs" do
      assert Types.validate_type(%TestStruct{}, {:struct, TestStruct}) == :ok
      assert {:error, _} = Types.validate_type(%{}, {:struct, TestStruct})
    end
  end

  describe "type_to_spec/1" do
    test "converts primitive types" do
      assert Types.type_to_spec(:integer) == quote(do: integer())
      assert Types.type_to_spec(:string) == quote(do: String.t())
    end

    test "converts list types" do
      spec = Types.type_to_spec({:list, :integer})
      assert spec == quote(do: [integer()])
    end
  end

  describe "default_for_type/1" do
    test "returns appropriate defaults" do
      assert Types.default_for_type(:list) == []
      assert Types.default_for_type({:list, :string}) == []
      assert Types.default_for_type({:enum, [:a, :b]}) == :a
    end
  end
end

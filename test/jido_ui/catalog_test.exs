defmodule Jido.UI.CatalogTest do
  use ExUnit.Case, async: true

  alias Jido.UI.Catalog
  alias JidoUITest.Fixtures

  test "a Catalog has a portable identity document and digest" do
    catalog = Fixtures.catalog()

    assert {:ok, document} = Catalog.document(catalog)
    assert document["type"] == "jido.ui.catalog"
    assert document["components"]["button"]["type"] == "object"

    assert document["capabilities"]["workspace.continue"]["event"] ==
             "workspace.continue"

    assert {:ok, _json} = Jason.encode(document)
    assert {:ok, digest} = Catalog.digest(catalog)
    assert byte_size(digest) == 64
    assert {:ok, ^digest} = Catalog.digest(catalog)
  end

  test "a Catalog rejects missing and non-Zoi component schemas" do
    assert {:error, %Jido.UI.Error{code: :invalid_catalog}} =
             Catalog.new("empty/v1", %{})

    assert {:error, %Jido.UI.Error{code: :invalid_catalog}} =
             Catalog.new("invalid/v1", %{"button" => %{}})
  end

  test "resolve revalidates a Catalog struct" do
    invalid = %{Fixtures.catalog() | components: %{}}

    assert {:error, %Jido.UI.Error{code: :invalid_catalog}} = Catalog.resolve(invalid)
  end

  test "canonical JSON does not depend on map insertion order" do
    left = %{"z" => [1, %{"b" => 2, "a" => 1}], "a" => true}
    right = %{"a" => true, "z" => [1, %{"a" => 1, "b" => 2}]}

    assert {:ok, left_json} = Jido.UI.JSON.encode_canonical(left)
    assert {:ok, ^left_json} = Jido.UI.JSON.encode_canonical(right)
    assert left_json == ~s({"a":true,"z":[1,{"a":1,"b":2}]})
  end
end

## roche/select（GraphQL 風選択取得）のテスト

import std/[unittest, json]
import ../src/roche/select

proc q(doc: JsonNode, sel: string): JsonNode =
  applySelection(parseSelection(sel), doc)

suite "selection":
  let doc = %*{
    "title": "t",
    "author": {"name": "n", "org": "o", "age": 3},
    "tags": ["a", "b"],
    "refs": [{"id": 1, "note": "x"}, {"id": 2, "note": "y"}]
  }

  test "トップレベルの選択":
    check q(doc, "{ title }") == %*{"title": "t"}

  test "ネストした選択":
    check q(doc, "{ author { name } }") == %*{"author": {"name": "n"}}

  test "カンマ・改行は空白扱い":
    check q(doc, "{\n  title,\n  author { name, org }\n}") ==
      %*{"title": "t", "author": {"name": "n", "org": "o"}}

  test "配列は要素ごとに適用（GraphQL のリスト透過）":
    check q(doc, "{ refs { id } }") == %*{"refs": [{"id": 1}, {"id": 2}]}

  test "存在しないフィールドは黙って省略":
    check q(doc, "{ title nosuch }") == %*{"title": "t"}

  test "leaf 指定は部分木を丸ごと":
    check q(doc, "{ author }") == %*{"author": {"name": "n", "org": "o", "age": 3}}

  test "スカラへの深い選択はスカラのまま":
    check q(doc, "{ title { x } }") == %*{"title": "t"}

  test "構文エラーは ValueError":
    expect ValueError: discard parseSelection("title")
    expect ValueError: discard parseSelection("{ title")
    expect ValueError: discard parseSelection("{ a } b")

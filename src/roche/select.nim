## roche/select — GraphQL 風の選択取得（設計書 §15）
##
## 取得したい値の「形」を宣言すると、その部分だけが返る:
##   "{ title author { name } }"
## クラスタモードではサーバ側で射影してから返すので、要らないフィールドは
## ネットワークを流れない。

import std/[json, tables]

type Selection* = ref object
  ## 選択木。fields が空 = leaf（その部分木を丸ごと取る）。
  ## 木構造で循環はない（ARC 制約, 設計書 §13.3）。
  fields*: OrderedTable[string, Selection]

type PreparedSelection* = object
  ## Validated reusable projection. Keeping the parsed tree prevents repeated
  ## parsing in embedded mode and prevents callers from interpolating values.
  source*: string
  tree*: Selection

proc isIdentChar(c: char): bool =
  c in {'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.'}

proc parseSel(src: string, pos: var int): Selection =
  result = Selection()
  # 呼び出し時点で src[pos] == '{'
  inc pos
  while pos < src.len:
    case src[pos]
    of ' ', '\t', '\n', '\r', ',':
      inc pos
    of '}':
      inc pos
      return
    of '{':
      raise newException(ValueError, "selection: フィールド名なしの '{'（位置 " & $pos & "）")
    else:
      if not isIdentChar(src[pos]):
        raise newException(ValueError, "selection: 不正な文字 '" & $src[pos] & "'（位置 " & $pos & "）")
      let start = pos
      while pos < src.len and isIdentChar(src[pos]): inc pos
      let name = src[start ..< pos]
      # フィールドの後に部分選択が続くか
      var look = pos
      while look < src.len and src[look] in {' ', '\t', '\n', '\r'}: inc look
      if look < src.len and src[look] == '{':
        pos = look
        result.fields[name] = parseSel(src, pos)
      else:
        result.fields[name] = nil   # leaf
  raise newException(ValueError, "selection: '}' で閉じていない")

proc parseSelection*(src: string): Selection =
  ## "{ a b { c } }" 形式を解析する。カンマは空白と同じ扱い（GraphQL 同様）。
  var pos = 0
  while pos < src.len and src[pos] in {' ', '\t', '\n', '\r'}: inc pos
  if pos >= src.len or src[pos] != '{':
    raise newException(ValueError, "selection: '{' で始まっていない")
  result = parseSel(src, pos)
  while pos < src.len:
    if src[pos] notin {' ', '\t', '\n', '\r'}:
      raise newException(ValueError, "selection: '}' の後に余分な入力")
    inc pos

proc prepareSelection*(src: string): PreparedSelection =
  PreparedSelection(source: src, tree: parseSelection(src))

proc applySelection*(sel: Selection, node: JsonNode): JsonNode =
  ## 選択木を JSON に適用して部分だけを返す。
  ## - オブジェクト: 選択したフィールドのうち存在するものだけ（欠けは黙って省略）
  ## - 配列: 各要素に同じ選択を適用（GraphQL のリスト透過と同じ）
  ## - スカラ: 選択の深さに関わらずそのまま
  if sel.isNil or sel.fields.len == 0:
    return node
  case node.kind
  of JObject:
    result = newJObject()
    for name, sub in sel.fields:
      if node.hasKey(name):
        result[name] = applySelection(sub, node[name])
  of JArray:
    result = newJArray()
    for elem in node:
      result.add applySelection(sel, elem)
  else:
    result = node

proc applySelection*(prepared: PreparedSelection, node: JsonNode): JsonNode =
  applySelection(prepared.tree, node)

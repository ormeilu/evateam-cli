"""Dotted-path projection shared by task JSON, text fields and TSV rows."""
from eva.json import JsonDoc, J_OBJ, J_ARR


def copy_path(
    src: JsonDoc,
    node: Int,
    parts: List[String],
    index: Int,
    mut dst: JsonDoc,
    result: Int,
) raises:
    if src.kind(node) == J_ARR:
        for i in range(src.len(node)):
            var item = src.at(node, i)
            var target: Int
            if dst.len(result) <= i:
                target = (
                    dst.array() if src.kind(item) == J_ARR else dst.object()
                )
                dst.push(result, target)
            else:
                target = dst.at(result, i)
            copy_path(src, item, parts, index, dst, target)
        return
    if src.kind(node) != J_OBJ:
        return
    var key = parts[index]
    var value = src.get(node, key)
    if value < 0:
        return
    if index == len(parts) - 1:
        var clone = dst.parse(src.dump(value))
        dst.set(result, key, clone)
        return
    if src.kind(value) != J_OBJ and src.kind(value) != J_ARR:
        return
    var child = dst.get(result, key)
    if child < 0:
        child = dst.array() if src.kind(value) == J_ARR else dst.object()
        dst.set(result, key, child)
    copy_path(src, value, parts, index + 1, dst, child)


def path_parts(path: String) raises -> List[String]:
    var out = List[String]()
    for part in path.split("."):
        if part == "":
            raise Error("empty field path component in " + path)
        out.append(String(part))
    return out^


def project_json(
    src: JsonDoc, root: Int, fields: List[String]
) raises -> String:
    var dst = JsonDoc()
    var result = dst.array() if src.kind(root) == J_ARR else dst.object()
    for field in fields:
        copy_path(src, root, path_parts(field), 0, dst, result)
    return dst.dump_pretty(result)


def path_text(
    src: JsonDoc, node: Int, parts: List[String], index: Int
) raises -> String:
    if src.kind(node) == J_ARR:
        var values = List[String]()
        for i in range(src.len(node)):
            values.append(path_text(src, src.at(node, i), parts, index))
        return ", ".join(values)
    if index == len(parts):
        return src.text(node)
    return path_text(src, src.get(node, parts[index]), parts, index + 1)


def column_text(src: JsonDoc, node: Int, path: String) raises -> String:
    return path_text(src, node, path_parts(path), 0)


def tsv_cell(value: String) -> String:
    return (
        value.replace("\\", "\\\\")
        .replace("\t", "\\t")
        .replace("\r", "\\r")
        .replace("\n", "\\n")
    )

"""Verify the requested subset of server-normalized field values."""
from eva.json import JsonDoc, J_OBJ, J_ARR, J_NUM, J_STR


def field_confirmed(
    expected: JsonDoc, e: Int, actual: JsonDoc, a: Int
) raises -> Bool:
    if a < 0:
        return False
    var ek = expected.kind(e)
    var ak = actual.kind(a)
    if ek == J_OBJ:
        if ak != J_OBJ:
            return False
        for i in range(expected.len(e)):
            if not field_confirmed(
                expected,
                expected.at(e, i),
                actual,
                actual.get(a, expected.key_at(e, i)),
            ):
                return False
        return True
    if ek == J_ARR:
        if ak != J_ARR or expected.len(e) != actual.len(a):
            return False
        var used = List[Int]()
        for i in range(expected.len(e)):
            var hit = -1
            for j in range(actual.len(a)):
                var taken = False
                for k in used:
                    if j == k:
                        taken = True
                if not taken and field_confirmed(
                    expected, expected.at(e, i), actual, actual.at(a, j)
                ):
                    hit = j
                    break
            if hit < 0:
                return False
            used.append(hit)
        return True
    if ek == J_STR and ak == J_OBJ:
        var value = expected.text(e)
        return value == actual.text_at(a, "id") or value == actual.text_at(
            a, "code"
        )
    if ek == J_NUM and ak == J_NUM:
        return Float64(expected.text(e)) == Float64(actual.text(a))
    return ek == ak and expected.text(e) == actual.text(a)


def require_fields(
    expected: JsonDoc, kw: Int, actual: JsonDoc, result: Int, code: String
) raises:
    for i in range(expected.len(kw)):
        var field = expected.key_at(kw, i)
        if not field_confirmed(
            expected, expected.at(kw, i), actual, actual.get(result, field)
        ):
            raise Error(
                code
                + " was written, but "
                + field
                + " was not confirmed by readback; inspect the task before"
                " retrying"
            )

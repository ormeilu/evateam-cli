"""Write planning is local: previews never call a mutation or invent IDs."""
from eva.json import JsonDoc


def preview_write(enabled: Bool, method: String, kwargs: String = "", args: String = "") raises -> Bool:
    if not enabled:
        return False
    var d = JsonDoc()
    var result = d.object()
    d.set_str(result, "method", method)
    if kwargs != "":
        var kw = d.parse(kwargs)
        d.set(result, "kwargs", kw)
    if args != "":
        var positional = d.parse(args)
        d.set(result, "args", positional)
    print("would send: " + d.dump(result))
    return True

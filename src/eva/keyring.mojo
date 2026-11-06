"""The OS keychain: one secret per profile under the service "eva-cli".

macOS uses the login keychain through Security.framework's generic-password
calls, which take plain C arguments. Linux uses the Secret Service (GNOME
Keyring, KWallet) through libsecret, loaded with dlopen, so a machine without
it still runs eva and only `auth login` reports what is missing.
"""

from std.ffi import OwnedDLHandle, RTLD, c_int
from std.memory.alloc import unsafe_alloc
from std.sys import CompilationTarget

from requests._dns import _cstr
from eva.term import stdin_is_tty

comptime SERVICE = "eva-cli"

# macOS OSStatus values worth naming.
comptime ERR_SEC_ITEM_NOT_FOUND: Int32 = -25300
comptime ERR_SEC_AUTH_FAILED: Int32 = -25293
comptime ERR_SEC_USER_CANCELED: Int32 = -128
comptime ERR_SEC_INTERACTION_NOT_ALLOWED: Int32 = -25308

comptime SECURITY = "/System/Library/Frameworks/Security.framework/Security"


def keyring_name() -> String:
    comptime if CompilationTarget.is_macos():
        return "the macOS Keychain"
    else:
        return "the Secret Service keyring"


def _c_string_at(addr: Int, length: Int = -1) -> String:
    """Copy a C string (or `length` bytes) at `addr`."""
    var p = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=addr)
    var bytes = List[UInt8]()
    var i = 0
    while (length < 0 and p[unsafe_offset=i] != 0) or (length >= 0 and i < length):
        bytes.append(p[unsafe_offset=i])
        i += 1
    return String(from_utf8_lossy=Span(bytes))


# ---- macOS ----


def _cannot_ask(what: String) -> Error:
    return Error(
        what + ": macOS wants to ask first (once after each install or upgrade of eva, or when"
        " the keychain is locked), and cannot ask outside a terminal. Run `eva auth status` in"
        " a terminal on this Mac and choose Always Allow"
    )


def _osstatus(code: Int32, what: String) -> Error:
    if code == ERR_SEC_AUTH_FAILED or code == ERR_SEC_USER_CANCELED:
        return Error(what + ": the keychain was not unlocked or access was denied")
    if code == ERR_SEC_INTERACTION_NOT_ALLOWED:
        return _cannot_ask(what)
    return Error(what + ": keychain error " + String(code))


def _mac_find(sec: OwnedDLHandle, profile: String, mut item: Int) raises -> Optional[String]:
    """The secret for `profile`; `item` gets the SecKeychainItemRef (or 0)."""
    var svc = _cstr(SERVICE)
    var acc = _cstr(profile)
    var len_out = unsafe_alloc[UInt32](1)
    var data_out = unsafe_alloc[Int](1)
    var item_out = unsafe_alloc[Int](1)
    len_out[unsafe_offset=0] = 0
    data_out[unsafe_offset=0] = 0
    item_out[unsafe_offset=0] = 0
    # A new build of eva is a new program to the keychain, so macOS shows a
    # dialog before the first read. Without a terminal (an agent, a script)
    # nobody may see it and eva would wait forever; fail with a hint instead.
    var interactive = stdin_is_tty()
    if not interactive:
        _ = sec.call["SecKeychainSetUserInteractionAllowed", Int32](UInt8(0))
    var status = sec.call["SecKeychainFindGenericPassword", Int32](
        Int(0),
        UInt32(SERVICE.byte_length()),
        svc,
        UInt32(profile.byte_length()),
        acc,
        len_out,
        data_out,
        item_out,
    )
    var result: Optional[String] = None
    var length = Int(len_out[unsafe_offset=0])
    var data = data_out[unsafe_offset=0]
    item = item_out[unsafe_offset=0]
    svc.unsafe_free()
    acc.unsafe_free()
    len_out.unsafe_free()
    data_out.unsafe_free()
    item_out.unsafe_free()
    if status == ERR_SEC_ITEM_NOT_FOUND:
        return None
    if not interactive and (status == ERR_SEC_AUTH_FAILED or status == ERR_SEC_INTERACTION_NOT_ALLOWED):
        raise _cannot_ask("reading the keychain")
    if status != 0:
        raise _osstatus(status, "reading the keychain")
    if data != 0:
        result = _c_string_at(data, length)
        _ = sec.call["SecKeychainItemFreeContent", Int32](Int(0), data)
    return result


def _mac_release(sec: OwnedDLHandle, item: Int):
    if item != 0:
        sec.call["CFRelease", NoneType](item)


def _mac_get(profile: String) raises -> Optional[String]:
    var sec = OwnedDLHandle(SECURITY)
    var item = 0
    var secret = _mac_find(sec, profile, item)
    _mac_release(sec, item)
    return secret


def _mac_set(profile: String, secret: String) raises:
    var sec = OwnedDLHandle(SECURITY)
    var item = 0
    _ = _mac_find(sec, profile, item)
    var pw = _cstr(secret)
    var status: Int32
    if item != 0:
        status = sec.call["SecKeychainItemModifyAttributesAndData", Int32](
            item, Int(0), UInt32(secret.byte_length()), pw
        )
        _mac_release(sec, item)
    else:
        var svc = _cstr(SERVICE)
        var acc = _cstr(profile)
        status = sec.call["SecKeychainAddGenericPassword", Int32](
            Int(0),
            UInt32(SERVICE.byte_length()),
            svc,
            UInt32(profile.byte_length()),
            acc,
            UInt32(secret.byte_length()),
            pw,
            Int(0),
        )
        svc.unsafe_free()
        acc.unsafe_free()
    pw.unsafe_free()
    if status != 0:
        raise _osstatus(status, "saving to the keychain")


def _mac_delete(profile: String) raises -> Bool:
    var sec = OwnedDLHandle(SECURITY)
    var item = 0
    _ = _mac_find(sec, profile, item)
    if item == 0:
        return False
    var status = sec.call["SecKeychainItemDelete", Int32](item)
    _mac_release(sec, item)
    if status != 0:
        raise _osstatus(status, "deleting from the keychain")
    return True


# ---- Linux: libsecret ----


struct _Secret:
    """libsecret and glib handles plus a schema with one "profile" attribute."""

    var ss: OwnedDLHandle
    var glib: OwnedDLHandle
    var schema: Pointer[UInt8, MutUntrackedOrigin]
    var schema_name: Pointer[UInt8, MutUntrackedOrigin]
    var attr_name: Pointer[UInt8, MutUntrackedOrigin]

    def __init__(out self) raises:
        # RTLD_NODELETE (glibc 0x1000): the GTypes libsecret registers stay in
        # gobject after dlclose, and loading it again over them deadlocks.
        comptime flags = RTLD.NOW | RTLD.GLOBAL | 0x1000
        try:
            self.ss = OwnedDLHandle("libsecret-1.so.0", flags)
            self.glib = OwnedDLHandle("libglib-2.0.so.0", flags)
        except:
            raise Error(
                "no keyring here: libsecret (the Secret Service client) is not"
                " installed. Install libsecret-1-0 and a keyring such as"
                " gnome-keyring, or set EVA_URL and EVA_API_KEY in the"
                " environment or in ~/.config/eva-cli/env"
            )
        # struct SecretSchema { const gchar *name; SecretSchemaFlags flags;
        #   SecretSchemaAttribute attributes[32]; gint reserved; gpointer reserved1..7; }
        # with SecretSchemaAttribute { const gchar *name; int type; } (16 bytes).
        # 1 KiB of zeros covers it and terminates the attribute list.
        self.schema = unsafe_alloc[UInt8](1024)
        for i in range(1024):
            self.schema[unsafe_offset=i] = 0
        self.schema_name = _cstr("org.ormeilu.eva-cli")
        self.attr_name = _cstr("profile")
        var words = self.schema.unsafe_bitcast[Int]()
        words[unsafe_offset=0] = Int(self.schema_name)  # name
        words[unsafe_offset=2] = Int(self.attr_name)  # attributes[0].name, type 0 = STRING

    def __deinit__(deinit self):
        self.schema.unsafe_free()
        self.schema_name.unsafe_free()
        self.attr_name.unsafe_free()

    def attributes(self, profile: Pointer[UInt8, MutUntrackedOrigin]) raises -> Int:
        """A GHashTable {"profile": profile}; the caller unrefs it."""
        var hash_fn = self.glib.get_symbol[UInt8]("g_str_hash")
        var equal_fn = self.glib.get_symbol[UInt8]("g_str_equal")
        if not hash_fn or not equal_fn:
            raise Error("glib lacks g_str_hash/g_str_equal")
        var table = self.glib.call["g_hash_table_new", Int](
            Int(hash_fn.unsafe_value()), Int(equal_fn.unsafe_value())
        )
        _ = self.glib.call["g_hash_table_insert", c_int](table, self.attr_name, profile)
        return table

    def unref(self, table: Int):
        self.glib.call["g_hash_table_unref", NoneType](table)


def _gerror(err: Pointer[Int, MutUntrackedOrigin], what: String) -> Error:
    """Turn a GError* into an Error; GError is { GQuark; gint; gchar *message }."""
    var e = err[unsafe_offset=0]
    var msg = String("unknown error")
    if e != 0:
        var words = Pointer[Int, MutUntrackedOrigin](unsafe_from_address=e)
        msg = _c_string_at(words[unsafe_offset=1])
    return Error(what + ": " + msg)


def _linux_get(profile: String) raises -> Optional[String]:
    var s = _Secret()
    var p = _cstr(profile)
    var table = s.attributes(p)
    var err = unsafe_alloc[Int](1)
    err[unsafe_offset=0] = 0
    var found = s.ss.call["secret_password_lookupv_sync", Int](s.schema, table, Int(0), err)
    s.unref(table)
    p.unsafe_free()
    var failed = err[unsafe_offset=0] != 0
    var error = _gerror(err, "reading the keyring")
    err.unsafe_free()
    if failed:
        raise error^
    if found == 0:
        return None
    var secret = _c_string_at(found)
    s.ss.call["secret_password_free", NoneType](found)
    return secret


def _linux_set(profile: String, secret: String) raises:
    var s = _Secret()
    var p = _cstr(profile)
    var label = _cstr("eva-cli: " + profile)
    var pw = _cstr(secret)
    var table = s.attributes(p)
    var err = unsafe_alloc[Int](1)
    err[unsafe_offset=0] = 0
    var ok = s.ss.call["secret_password_storev_sync", c_int](
        s.schema, table, Int(0), label, pw, Int(0), err
    )
    s.unref(table)
    p.unsafe_free()
    label.unsafe_free()
    pw.unsafe_free()
    var failed = ok == 0 or err[unsafe_offset=0] != 0
    var error = _gerror(err, "saving to the keyring")
    err.unsafe_free()
    if failed:
        raise error^


def _linux_delete(profile: String) raises -> Bool:
    var s = _Secret()
    var p = _cstr(profile)
    var table = s.attributes(p)
    var err = unsafe_alloc[Int](1)
    err[unsafe_offset=0] = 0
    var removed = s.ss.call["secret_password_clearv_sync", c_int](s.schema, table, Int(0), err)
    s.unref(table)
    p.unsafe_free()
    var failed = err[unsafe_offset=0] != 0
    var error = _gerror(err, "deleting from the keyring")
    err.unsafe_free()
    if failed:
        raise error^
    return removed != 0


# ---- public ----


def keyring_get(profile: String) raises -> Optional[String]:
    comptime if CompilationTarget.is_macos():
        return _mac_get(profile)
    else:
        return _linux_get(profile)


def keyring_set(profile: String, secret: String) raises:
    comptime if CompilationTarget.is_macos():
        _mac_set(profile, secret)
    else:
        _linux_set(profile, secret)


def keyring_delete(profile: String) raises -> Bool:
    comptime if CompilationTarget.is_macos():
        return _mac_delete(profile)
    else:
        return _linux_delete(profile)

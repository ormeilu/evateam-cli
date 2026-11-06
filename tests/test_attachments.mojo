"""File names and sizes for attachments."""

from std.testing import assert_equal, TestSuite

from eva.attachments import attachment_kwargs, human_size, safe_file_name


def test_human_size() raises:
    assert_equal(human_size(0), "0 B")
    assert_equal(human_size(1023), "1023 B")
    assert_equal(human_size(18275), "18 KB")
    assert_equal(human_size(1899867), "1.8 MB")
    assert_equal(human_size(1024 * 1024), "1.0 MB")


def test_safe_file_name_strips_paths() raises:
    assert_equal(safe_file_name("../../etc/passwd", "x"), "passwd")
    assert_equal(safe_file_name("C:\\Users\\a\\report.xlsx", "x"), "report.xlsx")
    assert_equal(safe_file_name("dir/", "ATT-1.bin"), "ATT-1.bin")


def test_safe_file_name_hidden_and_control() raises:
    assert_equal(safe_file_name(".bashrc", "x"), "bashrc")
    assert_equal(safe_file_name("..", "ATT-2.pdf"), "ATT-2.pdf")
    assert_equal(safe_file_name("a\nb\x1b[2Jc.txt", "x"), "ab[2Jc.txt")
    assert_equal(safe_file_name("Протокол 30.10.docx", "x"), "Протокол 30.10.docx")


def test_attachment_kwargs_by_code_or_id() raises:
    assert_equal(attachment_kwargs("ATT-1", "code"), '{"filter":["code","==","ATT-1"],"fields":["code"]}')
    assert_equal(
        attachment_kwargs("CmfAttachment:9", "code,url"), '{"filter":["id","==","CmfAttachment:9"],"fields":["code","url"]}'
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()

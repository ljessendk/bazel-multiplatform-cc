# new_local_repository(
#     name = "system_cc",
#     build_file_content = """
# filegroup(
#     name = 'system_cc',
#     srcs = glob([
#         'libexec/gcc/**',
#     ]),
#     visibility = ["//visibility:public"],    
# )
# """,
#         path = "/usr",
# )

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "rules_cc",
    urls = ["https://github.com/bazelbuild/rules_cc/releases/download/0.0.1/rules_cc-0.0.1.tar.gz"],
    sha256 = "4dccbfd22c0def164c8f47458bd50e0c7148f3d92002cdb459c2a96a68498241",
)
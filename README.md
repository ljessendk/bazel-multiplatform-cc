# Bazel multiplatform CC - proof of concept

This is a POC re-implementation of the build-in Bazel C/C++ rules in Starlark. The main motivation for this is to allow "transition free" C/C++ multiplatform builds in Bazel.

Features:
- API compatible with build-in C/C++ rules (https://bazel.build/reference/be/c-cpp)
- Written in Starlark.
- Allows explicitely setting the C/C++ toolchain for each target.

Limitations:
- Not feature complete, only cc_binary and cc_library are currently implemented (but easily extendable).
- Only tested with gcc compilers on Linux execution platforms.

# Usage

WORKSPACE:
```Starlark
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")
git_repository(
    name = "rules_multiplatform_cc",
    remote = "https://github.com/ljessendk/rules_multiplatform_cc.git",
    branch = "main",
)
```
BUILD (example showing build of 'hello' for 2 different architectures):
```Starlark
load("@rules_multiplatform_cc//cc:defs.bzl", "cc_binary")

[
    cc_binary(
        name = name,
        srcs = ["main.cpp"],
        toolchain = toolchain,
    )
    for (name, toolchain) in [
        ("hello_rpi", "//bazel/toolchain/aarch64-rpi3-linux-gnu:aarch64_toolchain"),
        ("hello_bbb", "//bazel/toolchain/arm-cortex_a8-linux-gnueabihf:armv7_toolchain"),
    ]
]
```

See https://ltekieli.com/cross-compiling-with-bazel/ for an example of how to configure toolchains.

# Concept

Unfortunately the current 'platform' concept in Bazel doesn't deal well with multi-platform builds, see fx. this thread on bazel-discuss: https://groups.google.com/g/bazel-discuss/c/-8T30fYg3UM/m/qhQYKuPMBwAJ. 
There is a feature request for adding multiplatform support for Bazel dating back to 2018 (https://github.com/bazelbuild/bazel/issues/6519) and apparently this issue is also on the "Bazel Configurability Roadmap", but progress seems very slow and it is unlikely that the issue will be solved soon.
The usual proposed workaround for 'multiplatform' builds is to use 'user defined transitions'. But user defined transitions are a pain to work with. Besides that they are complex to understand, require lots of boiler plate code, adds complexity to the build script and usually requires adding dummy 'copy' targets that makes your build slower, you will find yourself strugling with avoiding having platform independent things like generated headers being build multiple times (https://github.com/bazelbuild/bazel/issues/14023, https://github.com/bazelbuild/bazel/issues/14236).

This simple POC takes a different approach to multiplatform builds. Basically it bypasses the Bazel 'platform' concept and thus the need for 'platform' user defined transitions.

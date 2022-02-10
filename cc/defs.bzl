"""Rules for building C/C++ projects"""

load("@rules_cc//cc:action_names.bzl", "CPP_COMPILE_ACTION_NAME", "CPP_LINK_DYNAMIC_LIBRARY_ACTION_NAME", "CPP_LINK_EXECUTABLE_ACTION_NAME", "CPP_LINK_STATIC_LIBRARY_ACTION_NAME", "C_COMPILE_ACTION_NAME")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain")

DISABLED_FEATURES = [
    "module_maps",  # # copybara-comment-this-out-please
]

C_SUFFIX = [".c", ".C"]
CC_SUFFIX = [".cc", ".cpp", ".cxx", ".c++"]
HDR_SUFFIX = [".h", ".hh", ".hpp", ".hxx", ".inc", ".inl", ".H"]
ASM_SUFFIX = [".S"]
ARCHIVE_SUFFIX = [".a", ".pic.a"]
ALWAYS_LINK_SUFFIX = [".lo", ".pic.lo"]
SHARED_LIBRARY_SUFFIX = [".so", ".so.version"]
OBJECT_FILE_SUFFIX = [".o", ".pic.o"]

_common_attrs = {
    "deps": attr.label_list(providers = [CcInfo]),
    "srcs": attr.label_list(
        allow_files = C_SUFFIX + CC_SUFFIX + HDR_SUFFIX + ASM_SUFFIX + ARCHIVE_SUFFIX + ALWAYS_LINK_SUFFIX + SHARED_LIBRARY_SUFFIX + OBJECT_FILE_SUFFIX,
    ),
    "additional_linker_inputs": attr.label_list(),
    "copts": attr.string_list(),
    "defines": attr.string_list(),
    "includes": attr.string_list(),
    "linkopts": attr.string_list(),
    "local_defines": attr.string_list(),
    "malloc": attr.label(default = "@bazel_tools//tools/cpp:malloc"),
    "nocopts": attr.string(),
    "win_def_file": attr.label(),
    "toolchain": attr.label(providers = [cc_common.CcToolchainInfo]),
    #"_toolchain_files": attr.label(default = "@system_cc//:system_cc"),
    "_wrapper": attr.label(default = "//cc:compile_wrapper", allow_files = True),
}

def _has_suffix(file, suffix_list):
    for s in suffix_list:
        if file.path.endswith(s):
            return True
    return False

def _is_c(file):
    return _has_suffix(file, C_SUFFIX)

def _is_cc(file):
    return _has_suffix(file, CC_SUFFIX)

def _is_hdr(file):
    return _has_suffix(file, HDR_SUFFIX)

def _compile_file(*, actions, feature_configuration, cc_toolchain, src, all_hdrs_file, cc_compiler_path, action_name, user_compile_flags, compilation_context, name, wrapper):
    prefix = name + "_" + src.path
    obj_file = actions.declare_file(prefix + ".o")
    dep_file = actions.declare_file(prefix + ".d")

    compile_variables = cc_common.create_compile_variables(
        cc_toolchain = cc_toolchain,
        feature_configuration = feature_configuration,
        source_file = src.path,
        output_file = obj_file.path,
        user_compile_flags = user_compile_flags,
        include_directories = compilation_context.includes,
        quote_include_directories = compilation_context.quote_includes,
        system_include_directories = compilation_context.system_includes,
        framework_include_directories = compilation_context.framework_includes,
        preprocessor_defines = depset([], transitive = [compilation_context.defines, compilation_context.local_defines]),
        thinlto_index = None,  # TODO
        thinlto_input_bitcode_file = None,  # TODO
        thinlto_output_object_file = None,  # TODO
        use_pic = True,  # TODO
        add_legacy_cxx_options = False,  # TODO
        #variables_extension=unbound,    # TODO
    )

    command_line = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = action_name,
        variables = compile_variables,
    )
    env = cc_common.get_environment_variables(
        feature_configuration = feature_configuration,
        action_name = action_name,
        variables = compile_variables,
    )

    unused_file = actions.declare_file(prefix + ".unused")
    args = actions.args()

    # Arguments for wrapper
    # We need to use a wrapper to generate the 'unused inputs list'
    args.add(all_hdrs_file)
    args.add(dep_file)
    args.add(unused_file)

    # Compiler arguments
    args.add(cc_compiler_path)
    args.add_all(command_line)
    args.add("-MMD")
    args.add("-MF", dep_file)
    actions.run(
        outputs = [obj_file, dep_file, unused_file],
        inputs = depset(
            direct = [src, all_hdrs_file, wrapper],
            transitive = [
                compilation_context.headers,
                cc_toolchain.all_files,
            ],
        ),
        env = env,
        executable = wrapper,
        arguments = [args],
        unused_inputs_list = unused_file,
    )
    return obj_file

# Replacement for cc_common.compile()
# TODO: remove fragments
# TODO: remove wrapper
def _compile(*, actions, feature_configuration, cc_toolchain, srcs = [], public_hdrs = [], private_hdrs = [], includes = [], quote_includes = [], system_includes = [], framework_includes = [], defines = [], local_defines = [], include_prefix = "", strip_include_prefix = "", user_compile_flags = [], compilation_contexts = [], name, disallow_pic_outputs = False, disallow_nopic_outputs = False, additional_inputs = [], grep_includes = None, fragments, wrapper):
    local_compilation_context = cc_common.create_compilation_context(
        headers = depset(public_hdrs + private_hdrs),
        system_includes = depset(system_includes),
        includes = depset(includes),
        quote_includes = depset(quote_includes),
        framework_includes = depset(framework_includes),
        defines = depset(defines),
        local_defines = depset(local_defines),
    )

    all_compilation_context = cc_common.merge_compilation_contexts(compilation_contexts = compilation_contexts + [local_compilation_context])

    c_compiler_path = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = C_COMPILE_ACTION_NAME,
    )
    cpp_compiler_path = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = CPP_COMPILE_ACTION_NAME,
    )

    obj_files = []
    all_hdrs = all_compilation_context.direct_headers
    all_hdrs_file = actions.declare_file(name + ".all_hdrs")
    actions.write(
        all_hdrs_file,
        " ".join([x.path for x in all_hdrs]),
    )

    for input in srcs:
        if _is_c(input) or _is_cc(input):
            obj_files.append(
                _compile_file(
                    actions = actions,
                    src = input,
                    all_hdrs_file = all_hdrs_file,
                    cc_toolchain = cc_toolchain,
                    feature_configuration = feature_configuration,
                    cc_compiler_path = c_compiler_path if _is_c(input) else cpp_compiler_path,
                    action_name = C_COMPILE_ACTION_NAME if _is_c(input) else CPP_COMPILE_ACTION_NAME,
                    user_compile_flags = fragments.cpp.copts + (fragments.cpp.conlyopts if _is_c(input) else fragments.cpp.cxxopts),
                    compilation_context = all_compilation_context,
                    name = name,
                    wrapper = wrapper,
                ),
            )
        else:
            fail("Don't know how to handle source file: " + str(input.path))

    compilation_outputs = cc_common.create_compilation_outputs(pic_objects = depset(obj_files))

    return (local_compilation_context, compilation_outputs)

def _compile_files(*, actions, feature_configuration, cc_toolchain, srcs = [], hdrs = [], includes = [], quote_includes = [], system_includes = [], framework_includes = [], defines = [], local_defines = [], include_prefix = "", strip_include_prefix = "", user_compile_flags = [], compilation_contexts = [], name, disallow_pic_outputs = False, disallow_nopic_outputs = False, additional_inputs = [], grep_includes = None, fragments, wrapper):
    public_hdrs = hdrs
    private_hdrs = []
    srcs_only = []
    for s in srcs:
        if _is_hdr(s):
            private_hdrs.append(s)
        else:
            srcs_only.append(s)

    # Bazel crashes if we run the below
    #cc_common.compile(actions = actions, feature_configuration = feature_configuration, cc_toolchain = cc_toolchain, srcs = srcs, public_hdrs = public_hdrs, private_hdrs = private_hdrs, includes = includes, quote_includes = quote_includes, system_includes = system_includes, framework_includes = framework_includes, defines = defines, local_defines = local_defines, include_prefix = include_prefix, strip_include_prefix = strip_include_prefix, user_compile_flags = user_compile_flags, compilation_contexts = compilation_contexts, name = name, disallow_pic_outputs = disallow_pic_outputs, disallow_nopic_outputs = disallow_nopic_outputs, additional_inputs = additional_inputs, grep_includes = grep_includes)

    return _compile(
        actions = actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        srcs = srcs_only,
        public_hdrs = public_hdrs,
        private_hdrs = private_hdrs,
        includes = includes,
        quote_includes = quote_includes,
        system_includes = system_includes,
        framework_includes = framework_includes,
        defines = defines,
        local_defines = local_defines,
        include_prefix = include_prefix,
        strip_include_prefix = strip_include_prefix,
        user_compile_flags = user_compile_flags,
        compilation_contexts = compilation_contexts,
        name = name,
        disallow_pic_outputs = disallow_pic_outputs,
        disallow_nopic_outputs = disallow_nopic_outputs,
        additional_inputs = additional_inputs,
        grep_includes = grep_includes,
        fragments = fragments,  # TODO: remove this
        wrapper = wrapper,  # TODO: remove this
    )

def _merge_linking_contexts(linking_contexts):
    return cc_common.merge_cc_infos(cc_infos = [CcInfo(linking_context = x) for x in linking_contexts]).linking_context

LinkingOutputs = provider(fields = ['executable', 'library_to_link'])

# Replacement for cc_common.link
# TODO: remove win_def_file
def _link(*, actions, feature_configuration, cc_toolchain, compilation_outputs = None, user_link_flags = [], linking_contexts = [], name, language = "c++", output_type = "executable", link_deps_statically = True, stamp = 0, additional_inputs = [], grep_includes = None, additional_outputs = [], win_def_file = None):
    obj_files = compilation_outputs.pic_objects if compilation_outputs != None else None

    if output_type == "executable":
        action_name = CPP_LINK_EXECUTABLE_ACTION_NAME
        output_file = actions.declare_file(name)
        executable = output_file
        library_to_link = None
    elif output_type == "dynamic_library":
        action_name = CPP_LINK_DYNAMIC_LIBRARY_ACTION_NAME
        output_file = actions.declare_file("lib" + name + ".so")
        executable = None
        library_to_link = cc_common.create_library_to_link(
            actions = actions,
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            #static_library = static_lib_file,  # TODO
            pic_static_library = None,  # TODO
            dynamic_library = output_file,
            interface_library = None,  # TODO
            #pic_objects = None, # Marked as 'experimental; do not use'
            #objects = obj_files, # Marked as 'experimental; do not use'
            alwayslink = False,  # TODO
            dynamic_library_symlink_path = "",  # TODO
            interface_library_symlink_path = "",  # TODO
        )

    else:
        fail("Unknown output_type: {}".format(output_type))

    linker_path = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = action_name,
    )
    linker_variables = cc_common.create_link_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_link_flags = user_link_flags,
        output_file = output_file.path,
        def_file = win_def_file,
    )
    command_line = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = action_name,
        variables = linker_variables,
    )
    args = actions.args()
    args.add_all(command_line)
    if obj_files != None:
        args.add_all(obj_files)

    linking_context = _merge_linking_contexts(linking_contexts)
    pic_static_libraries = [y.pic_static_library for x in linking_context.linker_inputs.to_list() for y in x.libraries if y.pic_static_library != None]
    args.add_all(pic_static_libraries)

    env = cc_common.get_environment_variables(
        feature_configuration = feature_configuration,
        action_name = action_name,
        variables = linker_variables,
    )

    actions.run(
        executable = linker_path,
        arguments = [args],
        env = env,
        inputs = depset(
            direct = (obj_files if obj_files != None else []) + (pic_static_libraries if pic_static_libraries != None else []),
            transitive = [
                cc_toolchain.all_files,
            ],
        ),
        outputs = [output_file],
    )

    return LinkingOutputs(executable = executable, library_to_link = library_to_link)

# Alternative implementation of cc_common.create_linking_context_from_compilation_outputs
# TODO: remove owner (maybe use native.package_name)
def _create_linking_context_from_compilation_outputs(*, actions, feature_configuration, cc_toolchain, compilation_outputs, user_link_flags=[], linking_contexts=[], name, language='c++', alwayslink=False, additional_inputs=[], disallow_static_libraries=False, disallow_dynamic_library=False, grep_includes=None, owner):
    dynamic_library_linking_outputs = None
    if disallow_dynamic_library == False:
        dynamic_library_linking_outputs = _link(
            actions = actions,
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            compilation_outputs = compilation_outputs,
            user_link_flags = user_link_flags,
            linking_contexts = linking_contexts,
            name = name,
            language = "c++",
            output_type = "dynamic_library",
            link_deps_statically = True,    # TODO
            stamp = 0,
            additional_inputs = additional_inputs,
            grep_includes = None,
            #additional_outputs=unbound,
            #win_def_file = ctx.attr.win_def_file,
        )
    static_library_to_link = None
    if disallow_static_libraries == False:
        static_library_to_link = _cc_static_library(actions = actions, name = name, feature_configuration = feature_configuration, cc_toolchain = cc_toolchain, obj_files = compilation_outputs.pic_objects)

    linker_input = cc_common.create_linker_input(
        owner = owner,
        libraries = depset(direct = [dynamic_library_linking_outputs.library_to_link] if dynamic_library_linking_outputs != None else [], transitive = [
            depset([static_library_to_link] if static_library_to_link != None else [])
        ])
    )

    linking_context = cc_common.create_linking_context(linker_inputs = depset(direct = [linker_input]))

    return (linking_context, dynamic_library_linking_outputs)

def _cc_binary_impl(ctx):
    cc_toolchain = ctx.attr.toolchain[cc_common.CcToolchainInfo] if ctx.attr.toolchain != None else find_cc_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = DISABLED_FEATURES + ctx.disabled_features,
    )

    (compilation_context, compilation_outputs) = _compile_files(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        srcs = ctx.files.srcs,
        hdrs = [],
        includes = ctx.attr.includes,
        quote_includes = [],
        system_includes = [],
        framework_includes = [],
        defines = ctx.attr.defines,
        local_defines = ctx.attr.local_defines,
        include_prefix = "",
        strip_include_prefix = "",
        user_compile_flags = ctx.attr.copts,
        #compilation_contexts = [cc_info.compilation_context],
        compilation_contexts = [dep[CcInfo].compilation_context for dep in ctx.attr.deps],
        name = ctx.label.name,
        disallow_pic_outputs = False,
        disallow_nopic_outputs = False,
        additional_inputs = [],
        grep_includes = None,
        fragments = ctx.fragments,  # TODO: remove this
        wrapper = ctx.files._wrapper[0],  # TODO: remove this
    )

    linking_outputs = _link(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = compilation_outputs,
        user_link_flags = ctx.fragments.cpp.linkopts,
        #linking_contexts = [cc_info.linking_context],
        linking_contexts = [dep[CcInfo].linking_context for dep in ctx.attr.deps],
        name = ctx.label.name,
        language = "c++",
        output_type = "executable",
        link_deps_statically = True,
        stamp = 0,
        additional_inputs = ctx.attr.additional_linker_inputs,
        grep_includes = None,
        #additional_outputs=unbound,
        #win_def_file = ctx.attr.win_def_file,
    )

    # TODO: build-in cc_binary provides: CcInfo, InstrumentedFilesInfo, DebugPackageInfo, CcLauncherInfo, OutputGroupInfo
    return DefaultInfo(files = depset([linking_outputs.executable]))
    #return DefaultInfo(files = depset([linking_outputs[0]]))

def _cc_static_library(*, actions, name, feature_configuration, cc_toolchain, obj_files):
    output_file = actions.declare_file("lib" + name + ".a")

    action_name = CPP_LINK_STATIC_LIBRARY_ACTION_NAME
    archiver_path = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = action_name,
    )

    archiver_variables = cc_common.create_link_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        output_file = output_file.path,
        is_using_linker = False,
    )
    command_line = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = action_name,
        variables = archiver_variables,
    )
    args = actions.args()
    args.add_all(command_line)
    args.add_all(obj_files)

    env = cc_common.get_environment_variables(
        feature_configuration = feature_configuration,
        action_name = action_name,
        variables = archiver_variables,
    )

    actions.run(
        executable = archiver_path,
        arguments = [args],
        env = env,
        inputs = depset(
            direct = obj_files,
            transitive = [
                cc_toolchain.all_files,
            ],
        ),
        outputs = [output_file],
    )

    library_to_link = cc_common.create_library_to_link(
        actions = actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        #pic_objects = obj_files,
        pic_static_library = output_file,
    )

    return library_to_link

def _cc_library_impl(ctx):
    cc_toolchain = ctx.attr.toolchain[cc_common.CcToolchainInfo] if ctx.attr.toolchain != None else find_cc_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = DISABLED_FEATURES + ctx.disabled_features,
    )

    (compilation_context, compilation_outputs) = _compile_files(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        srcs = ctx.files.srcs,
        hdrs = ctx.files.hdrs,
        includes = ctx.attr.includes,
        quote_includes = ctx.attr.includes,
        system_includes = [],
        framework_includes = [],
        defines = ctx.attr.defines,
        local_defines = ctx.attr.local_defines,
        include_prefix = ctx.attr.include_prefix,
        strip_include_prefix = ctx.attr.strip_include_prefix,
        user_compile_flags = ctx.attr.copts,
        compilation_contexts = [dep[CcInfo].compilation_context for dep in ctx.attr.deps + ctx.attr.implementation_deps],
        name = ctx.label.name,
        disallow_pic_outputs = False,
        disallow_nopic_outputs = False,
        additional_inputs = [],
        grep_includes = None,
        fragments = ctx.fragments,  # TODO: remove this
        wrapper = ctx.files._wrapper[0],  # TODO: remove this
    )

    (linking_context, linking_outputs) = _create_linking_context_from_compilation_outputs(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = compilation_outputs,
        user_link_flags=ctx.fragments.cpp.linkopts,
        linking_contexts=[dep[CcInfo].linking_context for dep in ctx.attr.deps + ctx.attr.implementation_deps],
        name = ctx.label.name,
        language='c++',
        alwayslink=False,
        additional_inputs=ctx.attr.additional_linker_inputs,
        disallow_static_libraries=False,
        disallow_dynamic_library=ctx.attr.linkstatic,
        grep_includes=None,
        owner = ctx.label,
    )

    #print(linking_context)
    #print(linking_outputs.executable)
    #print(linking_outputs.library_to_link)

    path = ctx.build_file_path
    path = path[0:path.rfind("/")]
    compilation_context = cc_common.merge_compilation_contexts(compilation_contexts = [
        cc_common.create_compilation_context(
            system_includes = depset([path]),
        ),
        compilation_context,
    ])

    deps_cc_info = cc_common.merge_cc_infos(
        direct_cc_infos =
            [cc_common.merge_cc_infos(direct_cc_infos = [dep[CcInfo] for dep in ctx.attr.deps])] +
            [CcInfo(linking_context = dep[CcInfo].linking_context) for dep in ctx.attr.implementation_deps],
    )

    cc_info = cc_common.merge_cc_infos(direct_cc_infos = [
        CcInfo(compilation_context = compilation_context, linking_context = linking_context),
        deps_cc_info,
    ])

    # build-in cc_library provides CcInfo, InstrumentedFilesInfo, OutputGroupInfo
    return [cc_info]

def _cc_binary_attrs():
    attrs = _common_attrs
    attrs.update(
        {
            "linkshared": attr.bool(default = False),
            "linkstatic": attr.bool(default = True),
        },
    )
    return attrs

cc_binary = rule(
    implementation = _cc_binary_impl,
    attrs = _cc_binary_attrs(),
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
)

def _cc_library_attrs():
    attrs = _common_attrs
    attrs.update(
        {
            "hdrs": attr.label_list(
                allow_files = HDR_SUFFIX,
            ),
            "implementation_deps": attr.label_list(providers = [CcInfo]),
            "allwayslink": attr.bool(),
            "include_prefix": attr.string(),
            "linkstatic": attr.bool(default = False),
            "strip_include_prefix": attr.string(),
            "textual_hdrs": attr.label_list(
                allow_files = HDR_SUFFIX,
            ),
        },
    )
    return attrs

cc_library = rule(
    implementation = _cc_library_impl,
    attrs = _cc_library_attrs(),
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
)

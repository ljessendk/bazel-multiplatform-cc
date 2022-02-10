FROM gitpod/workspace-full

RUN sudo wget -O /usr/local/bin/bazel https://github.com/bazelbuild/bazel/releases/download/5.0.0/bazel_nojdk-5.0.0-linux-x86_64 && sudo chmod 555 /usr/local/bin/bazel
RUN echo "startup --output_user_root=/workspace/bazel_output" > ~/.bazelrc

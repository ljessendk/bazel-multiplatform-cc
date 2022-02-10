#!/usr/bin/python3

import subprocess
import sys

all_hdrs_file_name = sys.argv[1]
dep_file_name = sys.argv[2]
unused_file_name = sys.argv[3]

command_line = sys.argv[4:]
print("Executing: " + " ".join(command_line))
r = subprocess.run(command_line)
if(r.returncode != 0):
    sys.exit(r.returncode)

with open(all_hdrs_file_name) as all_hdrs_file:
    all_hdrs = all_hdrs_file.read().split(' ')

with open(dep_file_name) as dep_file:
    deps = dep_file.read().split()[2:]

unused = [x for x in all_hdrs if x not in deps]

with open(unused_file_name, "w") as unused_file:
    unused_file.write("\n".join(unused))

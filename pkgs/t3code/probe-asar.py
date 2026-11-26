#!/usr/bin/env python3
"""Search the t3code asar for a literal and print context windows around hits.

Usage: probe-asar.py <asar> <needle> [before] [after] [max-hits]

A reading tool only. The asar is one 270 MB blob of concatenated files, so a
plain grep prints megabyte-long lines; this slices a fixed window instead.
"""
import sys

asar, needle = sys.argv[1], sys.argv[2].encode()
before = int(sys.argv[3]) if len(sys.argv) > 3 else 200
after = int(sys.argv[4]) if len(sys.argv) > 4 else 400
cap = int(sys.argv[5]) if len(sys.argv) > 5 else 10

data = open(asar, "rb").read()
n, at = 0, 0
while n < cap:
    i = data.find(needle, at)
    if i < 0:
        break
    n += 1
    at = i + len(needle)
    lo, hi = max(0, i - before), min(len(data), i + len(needle) + after)
    print("=== hit %d at %d ===" % (n, i))
    print(data[lo:hi].decode("utf-8", "replace"))
    print()
print("hits shown: %d (total found so far: %s)" % (n, "capped" if n == cap else n))

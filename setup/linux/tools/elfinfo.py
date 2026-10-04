#!/usr/bin/env python3
"""Minimal ELF inspector: prints needed libraries and GLIBC version requirements."""
import struct
import sys


def main(path: str) -> int:
    data = open(path, "rb").read()
    if data[:4] != b"\x7fELF":
        print("not an ELF file")
        return 1
    is64 = data[4] == 2
    little = data[5] == 1
    endian = "<" if little else ">"
    machine = struct.unpack_from(endian + "H", data, 18)[0]
    etype = struct.unpack_from(endian + "H", data, 16)[0]
    machine_names = {0x8664: "x86-64", 0xB7: "AArch64", 0x03: "i386"}
    type_names = {1: "ET_REL", 2: "ET_EXEC", 3: "ET_DYN"}
    print(f"class={'64' if is64 else '32'} machine={machine_names.get(machine, hex(machine))} "
          f"type={type_names.get(etype, etype)} size={len(data)} bytes")

    if not is64:
        return 0
    e_phoff = struct.unpack_from(endian + "Q", data, 32)[0]
    e_phentsize = struct.unpack_from(endian + "H", data, 54)[0]
    e_phnum = struct.unpack_from(endian + "H", data, 56)[0]

    dynamic = None
    loads = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from(endian + "I", data, off)[0]
        p_offset = struct.unpack_from(endian + "Q", data, off + 8)[0]
        p_vaddr = struct.unpack_from(endian + "Q", data, off + 16)[0]
        p_filesz = struct.unpack_from(endian + "Q", data, off + 32)[0]
        if p_type == 2:      # PT_DYNAMIC
            dynamic = (p_offset, p_filesz)
        elif p_type == 1:    # PT_LOAD
            loads.append((p_vaddr, p_offset, p_filesz))

    if not dynamic:
        print("no PT_DYNAMIC (static binary)")
        return 0

    def vaddr_to_offset(vaddr):
        for base, offset, size in loads:
            if base <= vaddr < base + size:
                return offset + (vaddr - base)
        return None

    off, size = dynamic
    entries = []
    for i in range(size // 16):
        tag, value = struct.unpack_from(endian + "qQ", data, off + i * 16)
        if tag == 0:
            break
        entries.append((tag, value))

    needed = []
    strtab = None
    for tag, value in entries:
        if tag == 5:
            strtab = value
        elif tag == 1:
            needed.append(value)
    if strtab is not None:
        base = vaddr_to_offset(strtab)
        if base is not None:
            print("needed:")
            for n in needed:
                end = data.index(b"\x00", base + n)
                print("  ", data[base + n:end].decode())
    print("versions:", sorted({v.decode() for v in __import__("re").findall(rb"GLIBC_2\.\d+", data)}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

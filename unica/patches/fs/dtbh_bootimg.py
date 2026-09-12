#!/usr/bin/env python3
# Copyright (c) 2025 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later
"""Unpack/repack Samsung DTBH legacy boot images.

Older Samsung boot images (e.g. Exynos 8895) use the pre-header-version
Android boot layout where the 32-bit word at offset 40 holds the device
tree blob size (dt_size) instead of the boot image header version. The
modern platform unpack_bootimg/mkbootimg tools read that word as
``header_version`` and, since it is a large value (>= 3), take the v3+
code path which then fails. This script handles that legacy format so
the boot ramdisk can be patched and the image repacked byte-for-byte,
preserving the appended DTBH device tree blob.
"""
import argparse
import json
import os
import struct


SEANDROID_FOOTER = b"SEANDROIDENFORCE"


def _num_pages(size, page_size):
    return (size + page_size - 1) // page_size


def _read_header(data):
    if data[0:8] != b"ANDROID!":
        raise ValueError("Not an Android boot image")
    info = struct.unpack("9I", data[8:8 + 9 * 4])
    return {
        "kernel_size": info[0],
        "kernel_addr": info[1],
        "ramdisk_size": info[2],
        "ramdisk_addr": info[3],
        "second_size": info[4],
        "second_addr": info[5],
        "tags_addr": info[6],
        "page_size": info[7],
        "dt_size": info[8],
        "os_version": struct.unpack("I", data[44:48])[0],
    }


def is_samsung_dtbh(data):
    """Return True if ``data`` is a Samsung DTBH legacy boot image."""
    if data[0:8] != b"ANDROID!":
        return False
    header = _read_header(data)
    if header["page_size"] not in (2048, 4096):
        return False
    dt_size = header["dt_size"]
    if dt_size == 0:
        return False
    page_size = header["page_size"]
    ks, rs, ss = (header["kernel_size"], header["ramdisk_size"],
                  header["second_size"])
    dt_off = page_size * (1 + _num_pages(ks, page_size)
                         + _num_pages(rs, page_size)
                         + _num_pages(ss, page_size))
    if dt_off + dt_size > len(data):
        return False
    return data[dt_off:dt_off + 4] == b"DTBH"


def unpack(data, output_dir):
    header = _read_header(data)
    page_size = header["page_size"]
    ks, rs, ss, dt = (header["kernel_size"], header["ramdisk_size"],
                      header["second_size"], header["dt_size"])

    kernel_off = page_size
    kernel = data[kernel_off:kernel_off + ks]

    ramdisk_off = page_size * (1 + _num_pages(ks, page_size))
    ramdisk = data[ramdisk_off:ramdisk_off + rs]

    second_off = page_size * (1 + _num_pages(ks, page_size)
                              + _num_pages(rs, page_size))
    second = data[second_off:second_off + ss] if ss else b""

    dt_off = page_size * (1 + _num_pages(ks, page_size)
                         + _num_pages(rs, page_size)
                         + _num_pages(ss, page_size))
    dt_blob = data[dt_off:dt_off + dt] if dt else b""

    os.makedirs(output_dir, exist_ok=True)
    with open(os.path.join(output_dir, "kernel"), "wb") as f:
        f.write(kernel)
    with open(os.path.join(output_dir, "ramdisk"), "wb") as f:
        f.write(ramdisk)
    if second:
        with open(os.path.join(output_dir, "second"), "wb") as f:
            f.write(second)
    if dt_blob:
        with open(os.path.join(output_dir, "dt"), "wb") as f:
            f.write(dt_blob)

    return {
        "page_size": page_size,
        "kernel_addr": header["kernel_addr"],
        "ramdisk_addr": header["ramdisk_addr"],
        "second_addr": header["second_addr"],
        "tags_addr": header["tags_addr"],
        "dt_size": header["dt_size"],
        "os_version": header["os_version"],
        "name": data[48:64],
        "cmdline": data[64:576],
        "id": data[576:608],
        "extra_cmdline": data[608:1632],
        "header_pad": data[1632:page_size],
    }


def repack(output_dir, info, out_path):
    page_size = info["page_size"]
    with open(os.path.join(output_dir, "kernel"), "rb") as f:
        kernel = f.read()
    with open(os.path.join(output_dir, "ramdisk"), "rb") as f:
        ramdisk = f.read()
    second = b""
    second_path = os.path.join(output_dir, "second")
    if os.path.exists(second_path):
        with open(second_path, "rb") as f:
            second = f.read()
    dt_blob = b""
    dt_path = os.path.join(output_dir, "dt")
    if os.path.exists(dt_path):
        with open(dt_path, "rb") as f:
            dt_blob = f.read()

    ks, rs, ss, dts = (len(kernel), len(ramdisk), len(second), len(dt_blob))

    header = bytearray(page_size)
    header[0:8] = b"ANDROID!"
    struct.pack_into("9I", header, 8,
                     ks, info["kernel_addr"],
                     rs, info["ramdisk_addr"],
                     ss, info["second_addr"],
                     info["tags_addr"], page_size, dts)
    struct.pack_into("I", header, 44, info["os_version"])
    header[48:64] = info["name"]
    header[64:576] = info["cmdline"]
    header[576:608] = info["id"]
    header[608:1632] = info["extra_cmdline"]
    if len(info["header_pad"]) == page_size - 1632:
        header[1632:page_size] = info["header_pad"]

    def write_page(f, blob):
        f.write(blob)
        rem = len(blob) % page_size
        if rem:
            f.write(b"\x00" * (page_size - rem))

    with open(out_path, "wb") as f:
        f.write(header)
        write_page(f, kernel)
        write_page(f, ramdisk)
        if second:
            write_page(f, second)
        if dt_blob:
            write_page(f, dt_blob)
        f.write(SEANDROID_FOOTER)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    ck = sub.add_parser("check", help="exit 0 if the image is a Samsung DTBH boot image")
    ck.add_argument("--boot_img", required=True)
    up = sub.add_parser("unpack", help="unpack a Samsung DTBH boot image")
    up.add_argument("--boot_img", required=True)
    up.add_argument("--out", required=True)
    rp = sub.add_parser("repack", help="repack a Samsung DTBH boot image")
    rp.add_argument("--dir", required=True)
    rp.add_argument("--info", required=True,
                    help="path to the json info file written by unpack")
    rp.add_argument("--out", required=True)
    args = parser.parse_args()

    if args.cmd == "check":
        with open(args.boot_img, "rb") as f:
            data = f.read()
        if not is_samsung_dtbh(data):
            raise SystemExit(1)
    elif args.cmd == "unpack":
        with open(args.boot_img, "rb") as f:
            data = f.read()
        if not is_samsung_dtbh(data):
            raise SystemExit("not a Samsung DTBH boot image")
        info = unpack(data, args.out)
        with open(os.path.join(args.out, "dtbh_info.json"), "w") as f:
            json.dump({k: v.hex() if isinstance(v, (bytes, bytearray))
                       else v for k, v in info.items()}, f)
    elif args.cmd == "repack":
        with open(args.info) as f:
            raw = json.load(f)
        info = {k: bytes.fromhex(v) if isinstance(v, str) and k in
                ("name", "cmdline", "id", "extra_cmdline", "header_pad") else v
                for k, v in raw.items()}
        repack(args.dir, info, args.out)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
import argparse
import pathlib
import plistlib
import re
import uuid


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("plist", type=pathlib.Path)
    parser.add_argument("--product", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--mlb", required=True)
    parser.add_argument("--uuid", required=True)
    parser.add_argument("--rom", required=True)
    args = parser.parse_args()

    if not re.fullmatch(r"[0-9A-Fa-f]{12}", args.rom):
        raise SystemExit("ROM must contain exactly 12 hexadecimal characters")
    uuid.UUID(args.uuid)

    with args.plist.open("rb") as stream:
        config = plistlib.load(stream)
    generic = config["PlatformInfo"]["Generic"]
    generic["SystemProductName"] = args.product
    generic["SystemSerialNumber"] = args.serial
    generic["MLB"] = args.mlb
    generic["SystemUUID"] = args.uuid.upper()
    generic["ROM"] = bytes.fromhex(args.rom)
    with args.plist.open("wb") as stream:
        plistlib.dump(config, stream, sort_keys=False)


if __name__ == "__main__":
    main()


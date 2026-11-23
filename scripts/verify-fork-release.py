"""Check the archived app, its two public update URLs and the actual Ed25519 signature."""
import base64
import plistlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


def verify(directory, repo, tag):
    root = f"https://github.com/{repo}/releases"
    sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    with open("resources/Info.plist", "rb") as template:
        key = plistlib.load(template)["SUPublicEDKey"]
    with tempfile.TemporaryDirectory() as tmp:
        pub = Path(tmp) / "public.der"
        # RFC 8410 SubjectPublicKeyInfo header for a raw Ed25519 public key.
        pub.write_bytes(bytes.fromhex("302a300506032b6570032100") + base64.b64decode(key, validate=True))
        for suffix in ("", "-Intel"):
            archive = directory / f"Cra{suffix}.zip"
            with zipfile.ZipFile(archive) as zipped:
                info = plistlib.loads(zipped.read("Cra.app/Contents/Info.plist"))
            feed = f"appcast{suffix.lower()}.xml"
            assert info["SUFeedURL"] == f"{root}/latest/download/{feed}"
            assert info["SUPublicEDKey"] == key
            signature = None
            for channel in ("", "-stable"):
                path = directory / f"appcast{channel}{suffix.lower()}.xml"
                items = ET.parse(path).findall("channel/item")
                assert len(items) == 1, path
                item = items[0]
                assert item.findtext(sparkle + "version") == info["CFBundleVersion"]
                assert item.findtext(sparkle + "shortVersionString") == info["CFBundleShortVersionString"]
                enclosure = item.find("enclosure").attrib
                assert enclosure["url"] == f"{root}/download/{tag}/{archive.name}"
                assert int(enclosure["length"]) == archive.stat().st_size
                sig = base64.b64decode(enclosure[sparkle + "edSignature"], validate=True)
                assert signature is None or sig == signature
                signature = sig
            sigfile = Path(tmp) / "signature"
            sigfile.write_bytes(signature)
            subprocess.run(["openssl", "pkeyutl", "-verify", "-rawin", "-pubin",
                            "-keyform", "DER", "-inkey", str(pub), "-sigfile", str(sigfile),
                            "-in", str(archive)], check=True)
            print(f"Verified {archive.name}, build {info['CFBundleVersion']}, both channels")


if __name__ == "__main__":
    verify(Path(sys.argv[1]), sys.argv[2], sys.argv[3])

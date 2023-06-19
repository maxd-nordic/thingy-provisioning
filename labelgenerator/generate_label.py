#!/usr/bin/env python3

import random
import argparse
import qrcode
import sys
import qrcode.image.svg
import io
import base64
import lxml.etree

svg_header = """
<svg
   xmlns:dc="http://purl.org/dc/elements/1.1/"
   xmlns:cc="http://creativecommons.org/ns#"
   xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
   xmlns:svg="http://www.w3.org/2000/svg"
   xmlns="http://www.w3.org/2000/svg"
   xmlns:xlink="http://www.w3.org/1999/xlink"
   xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd"
   xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape">
"""


def generate_qr_code_node(url, x, y, height, width):
    # Configure and create QR code image
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=0,
    )
    qr.add_data(url)
    image = qr.make_image()

    # Create an in-memory byte stream
    image_stream = io.BytesIO()

    # Save the image to the byte stream as PNG
    image.save(image_stream)

    # Get the byte stream value as a string
    image_stream.seek(0)
    image_bytes = image_stream.getvalue()

    # Encode the byte stream as base64
    base64_image = base64.b64encode(image_bytes).decode("utf-8")

    xlink_href = f"data:image/png;base64,{base64_image}\n"

    return f'{svg_header}<image y="{y}" x="{x}" id="qrcode" xlink:href="{xlink_href}" preserveAspectRatio="none" height="{height}" width="{width}" /></svg>'


allowed_characters = b"abcdefghijkmnpqrstuvwxyz23456789"
base_url = "https://solar.thingy.rocks"
imei_template = "123456789012345"
pin_template = "654321"
fingerprint_template = "1.7deak2"

parser = argparse.ArgumentParser(description="Generate Fingerprint and Label")
parser.add_argument(
    "production_run", help='hex string unique to this production run, e.g. "3"'
)
parser.add_argument("imei", help="IMEI number of device")
parser.add_argument("pin", help="nRF Cloud PIN of device")
parser.add_argument("label_template", help="template SVG file")

args = parser.parse_args()

tree = lxml.etree.parse(args.label_template)
namespace = {"inkscape": "http://www.inkscape.org/namespaces/inkscape"}
nodes = tree.xpath('//*[@inkscape:label="qrcode"]', namespaces=namespace)
if len(nodes) != 1:
    print("label_template does not contain qrcode node", file=sys.stderr)
    sys.exit(1)
rect = nodes[0]
layer = rect.getparent()

device_code = bytes(random.sample(allowed_characters, 6)).decode("ASCII")
fingerprint = f"{args.production_run}.{device_code}"
url = f"{base_url}/{fingerprint}"

qr_code_tree = lxml.etree.fromstring(
    generate_qr_code_node(
        url, rect.get("x"), rect.get("y"), rect.get("width"), rect.get("height")
    )
)
qr_code_node = qr_code_tree.getchildren()[0]
layer.replace(rect, qr_code_node)

tree_str = lxml.etree.tostring(tree).decode("ASCII")
tree_str = tree_str.replace(imei_template, args.imei)
tree_str = tree_str.replace(pin_template, args.pin)
tree_str = tree_str.replace(fingerprint_template, fingerprint)

with open(f"label-{args.imei}.svg", "w") as f:
    f.write(tree_str)

print(fingerprint)

"""
AWS Lambda: convert JPEG files uploaded to an S3 bucket into PDF files
stored in a second S3 bucket.
"""

import os
import struct
import logging
from urllib.parse import unquote_plus

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
OUTPUT_BUCKET = os.environ["OUTPUT_BUCKET"]
JPEG_EXTENSIONS = (".jpg", ".jpeg")


def read_jpeg_info(data: bytes):
    """Return (width, height, components) from a JPEG's SOF header."""
    if data[:2] != b"\xff\xd8":
        raise ValueError("Not a JPEG file (missing SOI marker)")

    i = 2
    while i < len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker == 0xFF or marker == 0x01 or 0xD0 <= marker <= 0xD7:
            i += 1 if marker == 0xFF else 2
            continue
        seg_len = struct.unpack(">H", data[i + 2:i + 4])[0]
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            height, width = struct.unpack(">HH", data[i + 5:i + 9])
            components = data[i + 9]
            return width, height, components
        i += 2 + seg_len

    raise ValueError("Could not find image size in JPEG header")


def jpeg_to_pdf(jpeg: bytes) -> bytes:
    """Wrap JPEG bytes in a single-page PDF sized to the image."""
    width, height, components = read_jpeg_info(jpeg)

    color_space = {1: "/DeviceGray", 3: "/DeviceRGB", 4: "/DeviceCMYK"}.get(components)
    if color_space is None:
        raise ValueError(f"Unsupported number of colour components: {components}")
    decode = " /Decode [1 0 1 0 1 0 1 0]" if components == 4 else ""

    content = f"q {width} 0 0 {height} 0 0 cm /Im0 Do Q".encode()

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height}] "
            f"/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>"
        ).encode(),
        (
            f"<< /Type /XObject /Subtype /Image /Width {width} /Height {height} "
            f"/ColorSpace {color_space} /BitsPerComponent 8 /Filter /DCTDecode"
            f"{decode} /Length {len(jpeg)} >>\nstream\n"
        ).encode() + jpeg + b"\nendstream",
        f"<< /Length {len(content)} >>\nstream\n".encode() + content + b"\nendstream",
    ]

    pdf = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for num, body in enumerate(objects, start=1):
        offsets.append(len(pdf))
        pdf += f"{num} 0 obj\n".encode() + body + b"\nendobj\n"

    xref_pos = len(pdf)
    pdf += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    for off in offsets:
        pdf += f"{off:010d} 00000 n \n".encode()
    pdf += (
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
        f"startxref\n{xref_pos}\n%%EOF\n"
    ).encode()
    return bytes(pdf)


def lambda_handler(event, context):
    results = []
    for record in event.get("Records", []):
        src_bucket = record["s3"]["bucket"]["name"]
        src_key = unquote_plus(record["s3"]["object"]["key"])

        if not src_key.lower().endswith(JPEG_EXTENSIONS):
            logger.info("Skipping non-JPEG object: %s", src_key)
            continue

        logger.info("Converting s3://%s/%s", src_bucket, src_key)
        obj = s3.get_object(Bucket=src_bucket, Key=src_key)
        pdf_bytes = jpeg_to_pdf(obj["Body"].read())

        dest_key = os.path.splitext(src_key)[0] + ".pdf"
        s3.put_object(
            Bucket=OUTPUT_BUCKET,
            Key=dest_key,
            Body=pdf_bytes,
            ContentType="application/pdf",
        )
        logger.info("Saved s3://%s/%s (%d bytes)", OUTPUT_BUCKET, dest_key, len(pdf_bytes))
        results.append(dest_key)

    return {"statusCode": 200, "converted": results}
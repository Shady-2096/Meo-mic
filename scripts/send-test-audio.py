#!/usr/bin/env python3
"""Synthetic Meo Mic phone: handshake, stream a sine wave, verify ACKs."""

from __future__ import annotations

import argparse
import math
import socket
import struct
import time

MAGIC = b"WM"
VERSION = 1
PORT = 48888
RATE = 48_000
CHUNK_FRAMES = 960


def packet(kind: int, sequence: int, payload: bytes = b"") -> bytes:
    return struct.pack(">2sBBI", MAGIC, VERSION, kind, sequence) + payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument("--seconds", type=float, default=3)
    parser.add_argument("--frequency", type=float, default=440)
    parser.add_argument("--amplitude", type=float, default=0.25)
    args = parser.parse_args()

    target = (args.host, args.port)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(1.0)
    sequence = 0
    sock.sendto(packet(1, sequence), target)
    sequence += 1
    response, _ = sock.recvfrom(64)
    if len(response) != 8 or response[:4] != b"WM\x01\x03":
        raise RuntimeError(f"invalid handshake ACK: {response!r}")

    started = time.monotonic()
    deadline = started + args.seconds
    next_send = started
    frame = 0
    ack_count = 1
    while time.monotonic() < deadline:
        samples = [
            int(max(0, min(1, args.amplitude)) * 32767 *
                math.sin(2 * math.pi * args.frequency * (frame + i) / RATE))
            for i in range(CHUNK_FRAMES)
        ]
        payload = struct.pack(f"<{CHUNK_FRAMES}h", *samples)
        sock.sendto(packet(0, sequence, payload), target)
        sequence += 1
        frame += CHUNK_FRAMES

        try:
            sock.settimeout(0.001)
            response, _ = sock.recvfrom(64)
            if response[:4] == b"WM\x01\x03":
                ack_count += 1
        except TimeoutError:
            pass

        next_send += CHUNK_FRAMES / RATE
        time.sleep(max(0, next_send - time.monotonic()))

    sock.sendto(packet(2, sequence), target)
    print(f"sent {frame} PCM frames; received {ack_count} ACK packet(s)")
    if ack_count < 2 and args.seconds >= 1:
        raise RuntimeError("streaming ACK cadence was not observed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

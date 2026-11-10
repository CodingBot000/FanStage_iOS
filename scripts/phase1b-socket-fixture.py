#!/usr/bin/env python3
"""Loopback-only WebSocket retry/late-frame fixture; no production server changes."""
import base64, hashlib, json, socketserver, struct, threading
from urllib.parse import urlsplit

counts = {}
lock = threading.Lock()
release = threading.Event()
drop = threading.Event()

def frame(payload):
    data = json.dumps(payload).encode()
    assert len(data) < 126
    return b'\x81' + bytes([len(data)]) + data

class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        sock = self.request
        sock.settimeout(8)
        data = b''
        try:
            while b'\r\n\r\n' not in data:
                chunk = sock.recv(4096)
                if not chunk: return
                data += chunk
                if len(data) > 32768: return
            lines = data.decode('iso-8859-1').split('\r\n')
            path = urlsplit(lines[0].split()[1]).path
            headers = {k.lower(): v.strip() for line in lines[1:] if ':' in line for k, v in [line.split(':', 1)]}
            if path == '/stats':
                with lock: body = json.dumps(counts).encode()
                sock.sendall(b'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: ' + str(len(body)).encode() + b'\r\n\r\n' + body)
                return
            if path == '/release/delayed':
                release.set(); sock.sendall(b'HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n'); return
            if path == '/release/reset':
                drop.set(); sock.sendall(b'HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n'); return
            room = path.rsplit('/', 1)[-1]
            with lock:
                counts[room] = counts.get(room, 0) + 1
                attempt = counts[room]
            if room in ('limit', 'cancel') or (room == 'reset' and attempt not in (6, 11)):
                sock.sendall(b'HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\nContent-Length: 0\r\n\r\n'); return
            key = headers.get('sec-websocket-key', '')
            accept = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
            sock.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + b'\r\n\r\n')
            if room == 'delayed' and attempt == 1:
                with lock: counts['delayed_held'] = 1
                release.wait(6)
            try:
                sock.sendall(frame({'type':'subscribed','headSequence':0}))
                if room == 'delayed' and attempt == 1:
                    with lock: counts['delayed_release_attempted'] = 1
            except OSError:
                with lock: counts['delayed_write_failed'] = 1
                return
            if room == 'reset' and attempt == 6:
                drop.wait(6)
                return
            while sock.recv(2048): pass
        except (OSError, ValueError, IndexError):
            pass

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with Server(('127.0.0.1', 28768), Handler) as server:
    server.serve_forever()

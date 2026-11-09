#!/usr/bin/env python3
"""Local test-only proxy: hide the first ACK and its sender event."""
import json
import socket
import socketserver
import struct
import threading

UPSTREAM = ('127.0.0.1', 28765)
dropped_id = None
lock = threading.Lock()

def exact(sock, count):
    out = b''
    while len(out) < count:
        part = sock.recv(count - len(out))
        if not part:
            raise EOFError
        out += part
    return out

def pipe(src, dst):
    try:
        while data := src.recv(8192):
            dst.sendall(data)
    except OSError:
        pass
    finally:
        try: dst.shutdown(socket.SHUT_WR)
        except OSError: pass

class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        global dropped_id
        client = self.request
        upstream = socket.create_connection(UPSTREAM)
        try:
            header = b''
            while not header.endswith(b'\r\n\r\n'):
                header += exact(client, 1)
                if len(header) > 32768: return
            header = b"\r\n".join(line for line in header.split(b"\r\n") if not line.lower().startswith(b"sec-websocket-extensions:"))
            upstream.sendall(header)
            threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
            if b'upgrade: websocket' not in header.lower():
                pipe(upstream, client)
                return
            reply = b''
            while not reply.endswith(b'\r\n\r\n'): reply += exact(upstream, 1)
            client.sendall(reply)
            print("handshake", reply.split(b"\r\n", 1)[0], flush=True)
            while True:
                head = exact(upstream, 2)
                size = head[1] & 127
                extension = b''
                if size == 126: extension = exact(upstream, 2); size = struct.unpack('!H', extension)[0]
                elif size == 127: extension = exact(upstream, 8); size = struct.unpack('!Q', extension)[0]
                payload = exact(upstream, size)
                packet = json.loads(payload) if head[0] & 15 == 1 else {}
                message = packet.get('message') or {}
                with lock:
                    if packet.get('type') == 'ack' and dropped_id is None:
                        dropped_id = message.get('clientMessageId')
                        continue
                    if packet.get('type') == 'message' and dropped_id and message.get('clientMessageId') == dropped_id:
                        continue
                client.sendall(head + extension + payload)
        except (EOFError, OSError, ValueError) as exc:
            print("proxy error", type(exc).__name__, flush=True)
        finally:
            upstream.close()

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with Server(('127.0.0.1', 28767), Handler) as server:
    server.serve_forever()

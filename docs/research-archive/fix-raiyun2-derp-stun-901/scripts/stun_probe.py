#!/usr/bin/env python3
"""External STUN binding probe (RFC 5389).
Sends a Binding Request to a DERP STUN port and reports whether a
Binding Response (XOR-MAPPED-ADDRESS) comes back from the public side.
Usage: stun_probe.py <host> <port> [timeout_s] [count]
"""
import os, socket, struct, sys, time

def probe(host, port, timeout):
    tid = os.urandom(12)
    req = struct.pack("!HH", 0x0001, 0x0000) + struct.pack("!I", 0x2112A442) + tid
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout)
    t0 = time.time()
    s.sendto(req, (host, port))
    try:
        data, src = s.recvfrom(2048)
    except socket.timeout:
        s.close()
        return None, time.time() - t0, None
    rtt = (time.time() - t0) * 1000.0
    s.close()
    msg_type, msg_len, cookie = struct.unpack("!HHI", data[:8])
    ok_type = msg_type == 0x0101
    ok_tid = data[8:20] == tid
    ok_cookie = cookie == 0x2112A442
    # walk attributes for XOR-MAPPED-ADDRESS (0x0020)
    xor_addr = None
    i = 20
    body = data[20:20 + msg_len]
    while i + 4 <= len(data):
        atype, alen = struct.unpack("!HH", data[i:i + 4])
        aval = data[i + 4:i + 4 + alen]
        if atype == 0x0020 and alen >= 8:
            fam = aval[1]
            xport = struct.unpack("!H", aval[2:4])[0] ^ (0x2112A442 >> 16)
            xipint = struct.unpack("!I", aval[4:8])[0] ^ 0x2112A442
            xor_addr = (socket.inet_ntoa(struct.pack("!I", xipint)), xport)
        i += 4 + alen + (alen % 2)
    return {
        "src": src, "type": hex(msg_type), "ok_type": ok_type,
        "ok_tid": ok_tid, "ok_cookie": ok_cookie, "xor_mapped": xor_addr,
        "raw_len": len(data),
    }, rtt, body

def main():
    host = sys.argv[1]
    port = int(sys.argv[2])
    timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
    count = int(sys.argv[4]) if len(sys.argv) > 4 else 5
    print(f"STUN probe -> {host}:{port} (count={count}, timeout={timeout}s)")
    got = 0
    for n in range(1, count + 1):
        res, rtt, _ = probe(host, port, timeout)
        ts = time.strftime("%H:%M:%S")
        if res is None:
            print(f"[{ts}] #{n}: TIMEOUT after {rtt:.1f}ms")
        else:
            got += 1
            print(f"[{ts}] #{n}: RESPONSE rtt={rtt:.1f}ms src={res['src']} "
                  f"type={res['type']} ok(type/tid/cookie)="
                  f"{res['ok_type']}/{res['ok_tid']}/{res['ok_cookie']} "
                  f"xor_mapped={res['xor_mapped']} bytes={res['raw_len']}")
    print(f"SUMMARY {got}/{count} responses")
    sys.exit(0 if got > 0 else 2)

if __name__ == "__main__":
    main()

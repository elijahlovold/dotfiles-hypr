#!/usr/bin/env python3
# Persistent MQTT -> unix-socket bridge for a Bambu Lab printer (X1/P1/A1
# family, LAN-only mode). Owns the one MQTT connection to the printer -
# reconnects, auth, TLS quirks, incremental-state merging all live here, not
# in Quickshell - and fans the merged state out as newline-delimited JSON to
# any number of local socket clients (normally just Bambu.qml). Runs as a
# long-lived systemd --user service; see bambu-statusd.service.
#
# Needs `paho-mqtt` (pip install paho-mqtt, or your distro's package).
#
# Config comes entirely from environment variables so the printer's LAN
# access code never has to live in a file inside this repo - see
# bambu-statusd.env.example and BambuConfig.qml.
import asyncio
import json
import os
import ssl
import sys

import paho.mqtt.client as mqtt

PRINTER_IP = os.environ["BAMBU_IP"]
SERIAL = os.environ["BAMBU_SERIAL"]
ACCESS_CODE = os.environ["BAMBU_ACCESS_CODE"]
SOCKET_PATH = os.environ.get(
    "BAMBU_SOCKET_PATH",
    os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "bambu-status.sock"),
)

REPORT_TOPIC = f"device/{SERIAL}/report"
REQUEST_TOPIC = f"device/{SERIAL}/request"
PUSHALL = json.dumps({"pushing": {"sequence_id": "0", "command": "pushall"}})

# gcode_state -> our normalized `state` field
STATE_MAP = {
    "IDLE": "idle",
    "RUNNING": "printing",
    "PAUSE": "paused",
    "FINISH": "finished",
    "FAILED": "error",
}

state = {
    "online": False,
    "state": "offline",
    "file": "",
    "percent": 0,
    "layer": 0,
    "totalLayers": 0,
    "remainingMin": 0,
    "nozzleTemp": 0,
    "nozzleTarget": 0,
    "bedTemp": 0,
    "bedTarget": 0,
}

clients = set()
loop = None  # bound once the asyncio loop is running; paho calls back from its own thread


def snapshot_line():
    return (json.dumps(state) + "\n").encode()


async def broadcast():
    line = snapshot_line()
    dead = []
    for w in clients:
        try:
            w.write(line)
            await w.drain()
        except Exception:
            dead.append(w)
    for w in dead:
        clients.discard(w)


def merge_report(report):
    # P1-series pushes incremental deltas, not full snapshots - only
    # overwrite fields actually present in this message so the rest of the
    # state doesn't get reset to zero between updates.
    if "gcode_state" in report:
        state["state"] = STATE_MAP.get(report["gcode_state"], report["gcode_state"].lower())
    if "subtask_name" in report:
        state["file"] = report["subtask_name"]
    if "mc_percent" in report:
        state["percent"] = report["mc_percent"]
    if "layer_num" in report:
        state["layer"] = report["layer_num"]
    if "total_layer_num" in report:
        state["totalLayers"] = report["total_layer_num"]
    if "mc_remaining_time" in report:
        state["remainingMin"] = report["mc_remaining_time"]
    if "nozzle_temper" in report:
        state["nozzleTemp"] = round(report["nozzle_temper"])
    if "nozzle_target_temper" in report:
        state["nozzleTarget"] = round(report["nozzle_target_temper"])
    if "bed_temper" in report:
        state["bedTemp"] = round(report["bed_temper"])
    if "bed_target_temper" in report:
        state["bedTarget"] = round(report["bed_target_temper"])
    state["online"] = True


def on_connect(client, userdata, flags, rc):
    client.subscribe(REPORT_TOPIC)
    client.publish(REQUEST_TOPIC, PUSHALL)


def on_disconnect(client, userdata, rc):
    state["online"] = False
    state["state"] = "offline"
    if loop:
        asyncio.run_coroutine_threadsafe(broadcast(), loop)


def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload)
    except json.JSONDecodeError:
        return
    report = payload.get("print")
    if not report:
        return
    merge_report(report)
    if loop:
        asyncio.run_coroutine_threadsafe(broadcast(), loop)


async def handle_client(reader, writer):
    clients.add(writer)
    try:
        writer.write(snapshot_line())  # send current state immediately, don't wait for the next MQTT push
        await writer.drain()
        await reader.read()  # blocks until the client disconnects
    except Exception:
        pass
    finally:
        clients.discard(writer)
        writer.close()


async def periodic_pushall(client):
    # Recovery/consistency net only - MQTT is push-based so this is not the
    # primary update path. P1-series hardware is documented as disliking
    # pushall more often than ~every 5 minutes.
    while True:
        await asyncio.sleep(300)
        client.publish(REQUEST_TOPIC, PUSHALL)


def make_client():
    try:
        return mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION1)
    except AttributeError:
        return mqtt.Client()  # paho-mqtt < 2.0


async def main():
    global loop
    loop = asyncio.get_running_loop()

    if os.path.exists(SOCKET_PATH):
        os.remove(SOCKET_PATH)

    client = make_client()
    client.username_pw_set("bblp", ACCESS_CODE)
    client.tls_set(cert_reqs=ssl.CERT_NONE)
    client.tls_insecure_set(True)
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_message = on_message
    client.connect_async(PRINTER_IP, 8883, keepalive=30)
    client.loop_start()  # runs the MQTT network loop on its own thread

    server = await asyncio.start_unix_server(handle_client, path=SOCKET_PATH)
    asyncio.ensure_future(periodic_pushall(client))
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)

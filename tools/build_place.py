"""Builds build/SlimeRanch.rbxlx from src/ without needing Rojo.

    python3 tools/build_place.py

Mirrors default.project.json:
  src/shared -> ReplicatedStorage.Shared
  src/server -> ServerScriptService.Server
  src/client -> StarterPlayer.StarterPlayerScripts.Client
*.server.luau -> Script, *.client.luau -> LocalScript, other .luau -> ModuleScript.
"""
import os
import sys
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ref_counter = 0


def ref():
    global ref_counter
    ref_counter += 1
    return f"RBX{ref_counter:08X}"


def cdata(text):
    # "]]>" can't appear inside CDATA; split it across two sections
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def item(cls, name, children=(), source=None):
    props = f'<string name="Name">{escape(name)}</string>'
    if source is not None:
        props += f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
    inner = "".join(children)
    return f'<Item class="{cls}" referent="{ref()}"><Properties>{props}</Properties>{inner}</Item>'


def scripts_from(folder):
    out = []
    path = os.path.join(ROOT, folder)
    for fname in sorted(os.listdir(path)):
        if not fname.endswith(".luau"):
            continue
        with open(os.path.join(path, fname), encoding="utf-8") as f:
            src = f.read()
        if fname.endswith(".server.luau"):
            out.append(item("Script", fname[: -len(".server.luau")], source=src))
        elif fname.endswith(".client.luau"):
            out.append(item("LocalScript", fname[: -len(".client.luau")], source=src))
        else:
            out.append(item("ModuleScript", fname[: -len(".luau")], source=src))
    return out


def main(out_path):
    body = "".join([
        item("ReplicatedStorage", "ReplicatedStorage", [item("Folder", "Shared", scripts_from("src/shared"))]),
        item("ServerScriptService", "ServerScriptService", [item("Folder", "Server", scripts_from("src/server"))]),
        item("StarterPlayer", "StarterPlayer", [
            item("StarterPlayerScripts", "StarterPlayerScripts", [item("Folder", "Client", scripts_from("src/client"))]),
        ]),
    ])
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
        + body + "</roblox>"
    )
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(xml)
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "SlimeRanch.rbxlx"))

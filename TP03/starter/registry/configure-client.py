#!/usr/bin/env python3
"""Installe uniquement les réglages client du TP03, sans redémarrer Docker."""
import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile


def backup(path):
    if not path.exists():
        return
    destination = path.with_name(path.name + ".tp03-backup")
    if not destination.exists():
        shutil.copy2(path, destination)
        print(f"Sauvegarde : {destination}")


def configure_engine(directory):
    certificate = Path(__file__).resolve().parent / "certs" / "ca.crt"
    if not certificate.is_file():
        raise SystemExit("Exécuter ./setup.sh avant la configuration client.")
    directory.mkdir(parents=True, exist_ok=True)
    daemon = directory / "daemon.json"
    settings = json.loads(daemon.read_text()) if daemon.exists() else {}
    mirrors = settings.setdefault("registry-mirrors", [])
    if not isinstance(mirrors, list):
        raise SystemExit("registry-mirrors doit être une liste ; configuration inchangée.")
    mirror = "http://localhost:5001"
    if mirror not in mirrors:
        mirrors.append(mirror)
    backup(daemon)
    # Remplacement atomique ; conserver les autres options du daemon.
    with tempfile.NamedTemporaryFile(mode="w", dir=directory, delete=False) as stream:
        json.dump(settings, stream, indent=2)
        stream.write("\n")
        temporary = stream.name
    os.replace(temporary, daemon)
    target = directory / "certs.d" / "registry.local:5000" / "ca.crt"
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists() or target.read_bytes() != certificate.read_bytes():
        backup(target)
        shutil.copyfile(certificate, target)
    print(f"CA installée : {target}")
    print(f"Mirror ajouté : {daemon}")


def configure_hosts():
    path = Path("/etc/hosts")
    content = path.read_text()
    for line in content.splitlines():
        fields = line.split("#", 1)[0].split()
        if "registry.local" in fields[1:]:
            if fields[0] != "127.0.0.1":
                raise SystemExit("registry.local existe avec une autre IP ; corriger /etc/hosts.")
            print("registry.local est déjà associé à 127.0.0.1.")
            return
    backup(path)
    with path.open("a") as stream:
        if content and not content.endswith("\n"):
            stream.write("\n")
        stream.write("127.0.0.1 registry.local # TP03\n")
    print("Entrée registry.local ajoutée à /etc/hosts.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("desktop", "linux", "hosts"))
    mode = parser.parse_args().mode
    if mode == "desktop":
        configure_engine(Path.home() / ".docker")
    elif mode == "linux":
        configure_engine(Path("/etc/docker"))
    else:
        configure_hosts()


if __name__ == "__main__":
    main()

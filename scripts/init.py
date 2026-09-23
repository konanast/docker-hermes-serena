#!/usr/bin/env python3
"""Non-destructive initialization; never regenerate existing secrets/config."""
import os
from pathlib import Path
import re
import secrets
import shutil
os.chdir(Path(__file__).resolve().parent.parent)
os.umask(0o077)
for name in ("state/hermes", "state/serena/.serena", "state/serena/.cache", "backups", "versions"):
    Path(name).mkdir(parents=True, exist_ok=True)
p = Path(".env")
if not p.exists():
    content = Path(".env.example").read_text()
    for key, value in {"PUID": str(os.getuid()), "PGID": str(os.getgid()),
                       "HERMES_API_KEY": secrets.token_hex(32)}.items():
        content = re.sub(r"^" + key + r"=.*$", key + "=" + value, content, flags=re.M)
    with p.open("x") as f:
        f.write(content)
    print("Created .env with a new API secret. Edit MODEL_BASE_URL, MODEL_NAME, MODEL_API_KEY.")
else:
    print("Kept existing .env unchanged. If HERMES_API_KEY is empty, set it with: openssl rand -hex 32")
for src, dest in (("config/hermes.yaml", "state/hermes/config.yaml"),
                  ("config/serena.yml", "state/serena/.serena/serena_config.yml")):
    if Path(dest).exists():
        print("Kept existing", dest)
    else:
        # Exclusive creation prevents accidental overwrites, including a concurrent init.
        with open(src, "rb") as source, open(dest, "xb") as target:
            shutil.copyfileobj(source, target)
        print("Created", dest)
print("Initialization complete. Existing project files and credentials were not changed.")

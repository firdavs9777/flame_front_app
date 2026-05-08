# Phase 1 — Chat Solidity Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the realtime chat layer end-to-end across the FastAPI backend (`flame_backend`) and the Flutter client (`flame`) — replacing raw WebSockets with Socket.IO, adding server-side idempotency, persistent client outbox, per-user `last_read_at` reads, multi-device sync, structured observability, and the first real test foundation in either repo.

**Spec:** `/Users/davis/Desktop/Personal/flame/docs/superpowers/specs/2026-05-08-phase-1-chat-solidity-design.md` (revision 3, approved)

**Architecture:** `python-socketio` mounted on FastAPI ASGI with `AsyncRedisManager` replacing the hand-rolled `RedisPubSub`; `socket_io_client` on Flutter with a `Riverpod` provider graph and a `SharedPreferences`-backed outbox. ACK-first / persist-then-broadcast send flow keyed on `(user_id, client_message_id)` for at-least-once-from-client / at-most-once-to-recipient with REST as recovery source of truth. Schema-additive migration adds `Conversation.participants[]` while keeping `user1_id`/`user2_id` dual-written for one release. Two-flag rollout: backend env `CHAT_V2_ENABLED` plus runtime `/v1/config` endpoint.

**Tech stack:**
- Backend: Python 3.11, FastAPI 0.109, MongoDB (motor 3.6, beanie 1.26), Redis 5, Socket.IO via `python-socketio[asyncio]>=5.11.2`, `prometheus_client`, `python-json-logger`, `pytest-asyncio`, `testcontainers`.
- Flutter: Dart 3.10.7, Flutter SDK, `flutter_riverpod 2.5`, `socket_io_client ^2.0.3+1`, `shared_preferences`, `package:http` (kept).

**Repo paths:**
- Backend: `/Users/davis/Desktop/Personal/flame_backend`
- Flutter: `/Users/davis/Desktop/Personal/flame`

**Conventions used in this plan:**
- All paths are absolute when crossing repos. Within a repo's section, paths are relative to that repo root.
- `@superpowers:test-driven-development` discipline applies — write failing test, verify red, implement, verify green, commit.
- Commit messages use `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `test:` prefixes; co-author trailer included automatically by the harness.
- No `--no-verify`, no `--force` push to main, no `git config` changes.
- Local services (mongod, redis) are assumed up after Task 0.1; if any task starts and they're down, restart them.

---

# Section 0 — Setup

### Task 0.1: Start local infrastructure & enable keyspace notifications

**Files:** none (operator commands only)

- [ ] **Step 1: Start local MongoDB and Redis**

```bash
brew services start mongodb-community
brew services start redis
brew services list | grep -E "mongodb-community|redis"
```
Expected: both show `started`.

- [ ] **Step 2: Enable Redis keyspace notifications (required for grace-period offline)**

```bash
redis-cli CONFIG SET notify-keyspace-events Ex
redis-cli CONFIG GET notify-keyspace-events
```
Expected output: `Ex`. Persist by editing `$(brew --prefix)/etc/redis.conf` if needed; this session's setting is sufficient for dev work.

- [ ] **Step 3: Verify connectivity**

```bash
redis-cli PING
mongosh --quiet --eval "db.runCommand({ping: 1})"
```
Expected: `PONG` and `{ ok: 1 }`.

---

### Task 0.2: Backend dependencies and module skeleton

**Files:**
- Modify: `flame_backend/requirements.txt`
- Create: `flame_backend/app/realtime/__init__.py`
- Create: `flame_backend/app/realtime/constants.py`
- Create: `flame_backend/tests/__init__.py`
- Create: `flame_backend/tests/realtime/__init__.py`

- [ ] **Step 1: Add new dependencies to `requirements.txt`**

Append at the end of `flame_backend/requirements.txt`:
```
# Realtime + observability (Phase 1)
python-socketio[asyncio]>=5.11.2,<6.0.0
python-engineio>=4.9.0,<5.0.0
prometheus-client>=0.20.0,<0.22.0
python-json-logger>=2.0.7,<3.0.0

# Test stack
pytest-asyncio==0.23.3
testcontainers[mongodb,redis]>=4.0.0,<5.0.0
```

- [ ] **Step 2: Install**

```bash
cd /Users/davis/Desktop/Personal/flame_backend
source venv/bin/activate
pip install -r requirements.txt
python -c "import socketio, engineio, prometheus_client; print(socketio.__version__, engineio.__version__)"
```
Expected: prints `5.11.x 4.9.x` (or higher within the pinned range).

- [ ] **Step 3: Create skeleton package**

Create `flame_backend/app/realtime/__init__.py` (empty file).

Create `flame_backend/app/realtime/constants.py` with:
```python
"""Single source of truth for realtime event names and timeouts."""
from typing import Final

# Server → client events
EVT_CONNECTION_READY: Final = "connection:ready"
EVT_FORCE_DISCONNECT: Final = "force_disconnect"
EVT_AUTH_TOKEN_EXPIRING: Final = "auth:token_expiring"
EVT_AUTH_TOKEN_EXPIRED: Final = "auth:token_expired"
EVT_MESSAGE_NEW: Final = "message:new"
EVT_MESSAGE_SENT: Final = "message:sent"
EVT_MESSAGE_EDITED: Final = "message:edited"
EVT_MESSAGE_DELETED: Final = "message:deleted"
EVT_REACTION_UPDATE: Final = "reaction:update"
EVT_PIN_UPDATE: Final = "pin:update"
EVT_MATCH_NEW: Final = "match:new"
EVT_TYPING_UPDATE: Final = "typing:update"
EVT_READ_UPDATE: Final = "read:update"
EVT_PRESENCE_UPDATE: Final = "presence:update"

# Client → server events
EVT_MESSAGE_SEND: Final = "message:send"
EVT_MESSAGE_READ: Final = "message:read"
EVT_TYPING_START: Final = "typing:start"
EVT_TYPING_STOP: Final = "typing:stop"
EVT_PRESENCE_SUBSCRIBE: Final = "presence:subscribe"
EVT_AUTH_TOKEN_REFRESHED: Final = "auth:token_refreshed"

# Disconnect reasons
REASON_TOKEN_EXPIRED: Final = "token_expired"
REASON_BANNED: Final = "banned"
REASON_SUPERSEDED: Final = "superseded"

# Timeouts (seconds)
HOT_CACHE_TTL: Final = 60
PRESENCE_GRACE_TTL: Final = 10
TYPING_KEY_TTL: Final = 4
IDEMPOTENCY_TTL: Final = 86_400
OFFLINE_QUEUE_TTL: Final = 86_400
OFFLINE_QUEUE_CAP: Final = 50
PING_INTERVAL: Final = 25
PING_TIMEOUT: Final = 60
TOKEN_EXPIRY_LEAD: Final = 120
MAX_DEVICES_PER_USER: Final = 3
CONTENT_LENGTH_CAP: Final = 4_000
CLIENT_MESSAGE_ID_CAP: Final = 64
DEVICE_ID_CAP: Final = 64

# Redis key formats
KEY_USER_HOT: Final = "user:hot:{user_id}"
KEY_PRESENCE_SIDS: Final = "presence:sids:{user_id}"
KEY_PRESENCE_PENDING_OFFLINE: Final = "presence:pending_offline:{user_id}"
KEY_TYPING: Final = "typing:{conversation_id}:{user_id}"
KEY_TYPING_INDEX: Final = "typing_index:{user_id}"
KEY_IDEMPOTENCY: Final = "idempotency:{user_id}:{client_message_id}"
KEY_OFFLINE_QUEUE: Final = "queue:offline:{user_id}"
KEY_QUEUE_LOCK: Final = "queue:lock:{user_id}"
KEY_REAPER_LOCK: Final = "realtime:reaper:lock"
KEY_PRESENCE_SUBSCRIBERS: Final = "presence:subscribers:{user_id}"

# Pub/sub channels
CHAN_USER_BANNED: Final = "user:banned"

# Message URL whitelist regex
MEDIA_URL_PATTERN: Final = (
    r"^https://"
    r"(my-projects-media\.sfo3\.cdn\.digitaloceanspaces\.com"
    r"|media\.tenor\.com"
    r"|media1\.tenor\.com)/.+"
)
```

Create `flame_backend/tests/__init__.py` and `flame_backend/tests/realtime/__init__.py` (both empty).

- [ ] **Step 4: Verify import paths**

```bash
cd /Users/davis/Desktop/Personal/flame_backend
python -c "from app.realtime import constants; print(constants.EVT_MESSAGE_NEW)"
```
Expected: `message:new`.

- [ ] **Step 5: Commit**

```bash
git add requirements.txt app/realtime/ tests/
git commit -m "chore: add realtime deps and module skeleton (Phase 1)"
```

---

### Task 0.3: Flutter dependencies and environment config

**Files:**
- Modify: `flame/pubspec.yaml`
- Create: `flame/lib/config/env.dart`
- Modify: `flame/lib/services/api_client.dart` (just the URL constant)

- [ ] **Step 1: Add Flutter dependency**

In `flame/pubspec.yaml` under `dependencies:` (alphabetical position), add:
```yaml
  socket_io_client: ^2.0.3+1
```

- [ ] **Step 2: Install**

```bash
cd /Users/davis/Desktop/Personal/flame
flutter pub get
```
Expected: resolves without conflicts. If a transitive `web_socket_channel` conflict surfaces, do not remove `web_socket_channel` yet — the legacy code path needs it during transition.

- [ ] **Step 3: Create `lib/config/env.dart`**

```dart
enum AppEnv { local, prod }

class EnvConfig {
  final AppEnv env;
  final String apiBase;
  final String wsBase;

  const EnvConfig._(this.env, this.apiBase, this.wsBase);

  static const _local = EnvConfig._(
    AppEnv.local,
    'http://localhost:8000/v1',
    'ws://localhost:8000',
  );

  static const _prod = EnvConfig._(
    AppEnv.prod,
    'https://flame.banatalk.com/v1',
    'wss://flame.banatalk.com',
  );

  static EnvConfig get current {
    const raw = String.fromEnvironment('APP_ENV', defaultValue: '');
    if (raw.toLowerCase() == 'local') return _local;
    if (raw.toLowerCase() == 'prod') return _prod;
    // Default by build mode: debug → local, release → prod.
    const isRelease = bool.fromEnvironment('dart.vm.product');
    return isRelease ? _prod : _local;
  }
}
```

- [ ] **Step 4: Wire `api_client.dart` to use the config**

In `flame/lib/services/api_client.dart`, replace the hard-coded base URL on line 7 (`static const String baseUrl = 'https://flame.banatalk.com/v1';`) with:
```dart
import '../config/env.dart';
// ...
static String get baseUrl => EnvConfig.current.apiBase;
```
Update any `const` callers if they break — they should not, since `baseUrl` was already a static.

- [ ] **Step 5: Verify analyze + run smoke**

```bash
cd /Users/davis/Desktop/Personal/flame
flutter analyze lib/config/ lib/services/api_client.dart
```
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/config/env.dart lib/services/api_client.dart
git commit -m "chore: add socket_io_client dep and env config"
```

---

# Section 1 — Backend realtime foundation

### Task 1.1: AsyncServer + Redis manager + ASGI mount

**Files:**
- Create: `flame_backend/app/realtime/server.py`
- Modify: `flame_backend/app/main.py`

- [ ] **Step 1: Create `app/realtime/server.py`**

```python
"""Socket.IO AsyncServer mounted on FastAPI's ASGI app."""
import logging
import socketio
from app.core.config import settings
from app.realtime import constants as rc

logger = logging.getLogger(__name__)

# CORS for the socket layer mirrors REST settings.
sio = socketio.AsyncServer(
    async_mode="asgi",
    cors_allowed_origins=settings.CORS_ORIGINS,
    cors_credentials=True,
    client_manager=socketio.AsyncRedisManager(settings.REDIS_URL),
    ping_interval=rc.PING_INTERVAL,
    ping_timeout=rc.PING_TIMEOUT,
    logger=False,
    engineio_logger=False,
)


def build_asgi_app(fastapi_app):
    """Wrap the FastAPI app with the Socket.IO ASGI app at /ws/socket.io/."""
    return socketio.ASGIApp(
        sio,
        other_asgi_app=fastapi_app,
        socketio_path="/ws/socket.io",
    )
```

- [ ] **Step 2: Mount in `app/main.py`**

At the end of `flame_backend/app/main.py`, after the existing `app.include_router(...)` block and before any conditionally-flagged code, append:

```python
# --- Realtime mount (Phase 1, gated by CHAT_V2_ENABLED) ---
if getattr(settings, "CHAT_V2_ENABLED", False):
    from app.realtime.server import build_asgi_app, sio
    from app.realtime import handlers  # noqa: F401  (registers @sio.event handlers)
    asgi_app = build_asgi_app(app)
else:
    asgi_app = app
```

Also at module level, expose `asgi_app = app` initially (before the conditional) so uvicorn finds it whether the flag is on or off:

```python
# After `app = FastAPI(...)`:
asgi_app = app  # default; replaced below if CHAT_V2_ENABLED
```

- [ ] **Step 3: Add `CHAT_V2_ENABLED` to settings**

In `flame_backend/app/core/config.py`, inside the `Settings` class (alphabetical position, near other booleans), add:
```python
    CHAT_V2_ENABLED: bool = False
```

- [ ] **Step 4: Add a placeholder `handlers.py` so the import works**

Create `flame_backend/app/realtime/handlers.py`:
```python
"""Socket.IO event handlers. Populated in subsequent tasks."""
from app.realtime.server import sio  # noqa: F401
```

- [ ] **Step 5: Smoke-run uvicorn with the flag on**

```bash
cd /Users/davis/Desktop/Personal/flame_backend
source venv/bin/activate
CHAT_V2_ENABLED=true uvicorn app.main:asgi_app --host 0.0.0.0 --port 8000 &
sleep 2
curl -s http://localhost:8000/health | head
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/ws/socket.io/?EIO=4\&transport=polling
kill %1
```
Expected: health returns 200, the Socket.IO polling endpoint returns 200 (Engine.IO handshake response, not a 404).

- [ ] **Step 6: Commit**

```bash
git add app/realtime/server.py app/realtime/handlers.py app/main.py app/core/config.py
git commit -m "feat: mount python-socketio AsyncServer with Redis manager"
```

---

### Task 1.2: Test fixture — testcontainers + AsyncSimpleClient harness

**Files:**
- Create: `flame_backend/tests/conftest.py`
- Create: `flame_backend/tests/realtime/conftest.py`
- Create: `flame_backend/pytest.ini`

- [ ] **Step 1: Create `pytest.ini`**

```ini
[pytest]
asyncio_mode = auto
testpaths = tests
filterwarnings =
    ignore::DeprecationWarning:passlib
```

- [ ] **Step 2: Create top-level `conftest.py`**

```python
"""Shared fixtures for backend tests."""
import asyncio
import pytest


@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()
```

- [ ] **Step 3: Create `tests/realtime/conftest.py`** with testcontainers + AsyncSimpleClient

```python
"""Realtime test fixtures — real Mongo + real Redis via testcontainers."""
import asyncio
import os
import socketio
import pytest
import pytest_asyncio
from beanie import init_beanie
from motor.motor_asyncio import AsyncIOMotorClient
from testcontainers.mongodb import MongoDbContainer
from testcontainers.redis import RedisContainer
from typing import AsyncIterator

from app.realtime import constants as rc


@pytest.fixture(scope="session")
def mongo_container():
    with MongoDbContainer("mongo:7") as c:
        yield c


@pytest.fixture(scope="session")
def redis_container():
    with RedisContainer("redis:7-alpine") as c:
        # Enable keyspace notifications for grace-period tests.
        c.get_client().config_set("notify-keyspace-events", "Ex")
        yield c


@pytest_asyncio.fixture
async def app_with_realtime(monkeypatch, mongo_container, redis_container) -> AsyncIterator:
    """Spin up the FastAPI+Socket.IO app against test containers."""
    monkeypatch.setenv("MONGODB_URL", mongo_container.get_connection_url())
    monkeypatch.setenv("MONGODB_DB_NAME", "flame_test")
    monkeypatch.setenv("REDIS_URL",
        f"redis://{redis_container.get_container_host_ip()}:"
        f"{redis_container.get_exposed_port(6379)}")
    monkeypatch.setenv("CHAT_V2_ENABLED", "true")

    # Reset settings + db modules to pick up new env vars.
    import importlib
    from app.core import config as cfg_mod
    importlib.reload(cfg_mod)
    from app.core import database as db_mod
    importlib.reload(db_mod)

    from app.core.database import connect_to_mongo, close_mongo_connection
    await connect_to_mongo()

    from app.realtime.server import sio, build_asgi_app
    from fastapi import FastAPI
    fastapi_app = FastAPI()

    # Register handlers (importing the module triggers @sio.event decorators)
    from app.realtime import handlers  # noqa: F401

    asgi_app = build_asgi_app(fastapi_app)

    import uvicorn
    config = uvicorn.Config(asgi_app, host="127.0.0.1", port=0, log_level="warning")
    server = uvicorn.Server(config)
    server_task = asyncio.create_task(server.serve())

    # Wait for uvicorn to bind a port.
    while not server.started:
        await asyncio.sleep(0.05)
    port = server.servers[0].sockets[0].getsockname()[1]

    yield {"sio": sio, "url": f"http://127.0.0.1:{port}", "port": port}

    server.should_exit = True
    await server_task
    await close_mongo_connection()


@pytest_asyncio.fixture
async def make_socket_client(app_with_realtime):
    """Factory that creates an AsyncSimpleClient connected to the test server."""
    clients = []

    async def _factory(token: str, device_id: str = "test-device"):
        client = socketio.AsyncSimpleClient()
        await client.connect(
            app_with_realtime["url"],
            socketio_path="/ws/socket.io",
            auth={"token": token, "device_id": device_id},
            transports=["websocket"],
        )
        clients.append(client)
        return client

    yield _factory

    for c in clients:
        await c.disconnect()
```

- [ ] **Step 4: Verify the fixture lifecycle compiles & boots**

Add a stub test `tests/realtime/test_fixtures_smoke.py`:
```python
import pytest


@pytest.mark.asyncio
async def test_app_boots(app_with_realtime):
    assert app_with_realtime["url"].startswith("http://")
```

```bash
cd /Users/davis/Desktop/Personal/flame_backend
source venv/bin/activate
pytest tests/realtime/test_fixtures_smoke.py -v
```
Expected: PASS in <30s (testcontainers may pull images on first run).

- [ ] **Step 5: Commit**

```bash
git add pytest.ini tests/conftest.py tests/realtime/conftest.py tests/realtime/test_fixtures_smoke.py
git commit -m "test: add testcontainers + Socket.IO test harness"
```

---

### Task 1.3: `connect` handler with JWT auth + device_id check (TDD)

**Files:**
- Create: `flame_backend/app/realtime/auth.py`
- Modify: `flame_backend/app/realtime/handlers.py`
- Create: `flame_backend/tests/realtime/test_connect.py`

- [ ] **Step 1: Write failing test**

`tests/realtime/test_connect.py`:
```python
import pytest
import socketio
from app.core.security import create_access_token


@pytest.mark.asyncio
async def test_connect_with_valid_token(make_socket_client, seed_user):
    user = await seed_user()
    token = create_access_token({"sub": str(user.id)})
    client = await make_socket_client(token)
    event = await client.receive(timeout=2)
    assert event[0] == "connection:ready"
    assert event[1]["user_id"] == str(user.id)


@pytest.mark.asyncio
async def test_connect_rejects_missing_token(app_with_realtime):
    client = socketio.AsyncSimpleClient()
    with pytest.raises(socketio.exceptions.ConnectionError):
        await client.connect(
            app_with_realtime["url"],
            socketio_path="/ws/socket.io",
            transports=["websocket"],
        )


@pytest.mark.asyncio
async def test_connect_rejects_refresh_token(app_with_realtime, seed_user):
    user = await seed_user()
    from app.core.security import create_refresh_token
    refresh, _ = create_refresh_token({"sub": str(user.id)})
    client = socketio.AsyncSimpleClient()
    with pytest.raises(socketio.exceptions.ConnectionError):
        await client.connect(
            app_with_realtime["url"],
            socketio_path="/ws/socket.io",
            auth={"token": refresh, "device_id": "d"},
            transports=["websocket"],
        )


@pytest.mark.asyncio
async def test_connect_rejects_long_device_id(app_with_realtime, seed_user):
    user = await seed_user()
    token = create_access_token({"sub": str(user.id)})
    client = socketio.AsyncSimpleClient()
    with pytest.raises(socketio.exceptions.ConnectionError):
        await client.connect(
            app_with_realtime["url"],
            socketio_path="/ws/socket.io",
            auth={"token": token, "device_id": "x" * 65},
            transports=["websocket"],
        )
```

Add a `seed_user` fixture in `tests/realtime/conftest.py`:
```python
@pytest_asyncio.fixture
async def seed_user(app_with_realtime):
    from app.models.user import User, Gender
    counter = {"n": 0}

    async def _make():
        counter["n"] += 1
        u = User(
            email=f"u{counter['n']}@test.local",
            password_hash="x",
            name=f"u{counter['n']}",
            age=25,
            gender=Gender.MALE,
            looking_for=Gender.FEMALE,
            interests=["x"],
        )
        await u.insert()
        return u

    return _make
```

- [ ] **Step 2: Run, verify red**

```bash
pytest tests/realtime/test_connect.py -v
```
Expected: all 4 fail (handler not implemented).

- [ ] **Step 3: Implement `app/realtime/auth.py`**

```python
"""Socket.IO authentication and session helpers."""
import json
import logging
import time
import redis.asyncio as aioredis
from socketio.exceptions import ConnectionRefusedError as SioConnectionRefused

from app.core.config import settings
from app.core.security import decode_token
from app.models.user import User
from app.realtime import constants as rc

logger = logging.getLogger(__name__)
_redis: aioredis.Redis | None = None


def get_redis() -> aioredis.Redis:
    global _redis
    if _redis is None:
        _redis = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    return _redis


async def authenticate_handshake(auth: dict | None) -> tuple[str, str]:
    """Validate the connect-time auth payload. Returns (user_id, device_id)
    or raises ConnectionRefusedError."""
    if not auth or not isinstance(auth, dict):
        raise SioConnectionRefused("auth payload missing")
    token = auth.get("token")
    device_id = auth.get("device_id")
    if not token or not isinstance(token, str):
        raise SioConnectionRefused("token missing")
    if not device_id or not isinstance(device_id, str) or len(device_id) > rc.DEVICE_ID_CAP:
        raise SioConnectionRefused("device_id missing or too long")
    payload = decode_token(token)
    if payload is None or payload.get("type") != "access":
        raise SioConnectionRefused("invalid or non-access token")
    user_id = payload.get("sub")
    if not user_id:
        raise SioConnectionRefused("token missing sub")
    return user_id, device_id


async def cache_user_hot(user_id: str) -> dict:
    """Load minimal user doc into Redis hot cache; return the dict."""
    user = await User.get(user_id)
    if user is None:
        raise SioConnectionRefused("user not found")
    if getattr(user, "is_banned", False):
        raise SioConnectionRefused("user banned")
    payload = {
        "id": str(user.id),
        "is_banned": bool(getattr(user, "is_banned", False)),
        "blocked_users": [str(b) for b in getattr(user, "blocked_users", [])],
    }
    await get_redis().set(
        rc.KEY_USER_HOT.format(user_id=user_id),
        json.dumps(payload),
        ex=rc.HOT_CACHE_TTL,
    )
    return payload
```

- [ ] **Step 4: Implement `connect` handler in `app/realtime/handlers.py`**

```python
"""Socket.IO event handlers."""
import time
import logging
from app.realtime.server import sio
from app.realtime import constants as rc
from app.realtime.auth import authenticate_handshake, cache_user_hot, get_redis

logger = logging.getLogger(__name__)


@sio.event
async def connect(sid: str, environ: dict, auth: dict | None = None):
    user_id, device_id = await authenticate_handshake(auth)
    await cache_user_hot(user_id)
    await sio.save_session(sid, {
        "user_id": user_id,
        "device_id": device_id,
        "connected_at": time.time(),
    })
    await sio.enter_room(sid, f"user:{user_id}")
    await sio.emit(
        rc.EVT_CONNECTION_READY,
        {"user_id": user_id, "sid": sid, "server_time": int(time.time() * 1000)},
        to=sid,
    )
```

- [ ] **Step 5: Run, verify green**

```bash
pytest tests/realtime/test_connect.py -v
```
Expected: all 4 PASS.

- [ ] **Step 6: Commit**

```bash
git add app/realtime/auth.py app/realtime/handlers.py tests/realtime/conftest.py tests/realtime/test_connect.py
git commit -m "feat(realtime): JWT-authenticated socket connect with device_id check"
```

---

### Task 1.4: Multi-device cap and `presence:sids` sorted-set bookkeeping (TDD)

**Files:**
- Create: `flame_backend/app/realtime/presence.py`
- Modify: `flame_backend/app/realtime/handlers.py`
- Create: `flame_backend/tests/realtime/test_multi_device.py`

- [ ] **Step 1: Write failing test**

`tests/realtime/test_multi_device.py`:
```python
import pytest
from app.core.security import create_access_token


@pytest.mark.asyncio
async def test_fourth_connection_evicts_oldest(make_socket_client, seed_user):
    user = await seed_user()
    token = create_access_token({"sub": str(user.id)})
    c1 = await make_socket_client(token, "d1")
    c2 = await make_socket_client(token, "d2")
    c3 = await make_socket_client(token, "d3")
    # Drain ready events
    for c in (c1, c2, c3):
        await c.receive(timeout=2)
    c4 = await make_socket_client(token, "d4")
    # c1 (oldest) should receive force_disconnect within 2s
    evt = await c1.receive(timeout=2)
    assert evt[0] == "force_disconnect"
    assert evt[1]["reason"] == "superseded"


@pytest.mark.asyncio
async def test_zset_tracks_active_sids(make_socket_client, seed_user):
    from app.realtime.auth import get_redis
    from app.realtime import constants as rc
    user = await seed_user()
    token = create_access_token({"sub": str(user.id)})
    c1 = await make_socket_client(token, "d1")
    await c1.receive(timeout=2)
    r = get_redis()
    count = await r.zcard(rc.KEY_PRESENCE_SIDS.format(user_id=str(user.id)))
    assert count == 1
```

- [ ] **Step 2: Run, verify red**

```bash
pytest tests/realtime/test_multi_device.py -v
```

- [ ] **Step 3: Implement `app/realtime/presence.py`**

```python
"""Presence + multi-device bookkeeping via Redis sorted-set."""
import time
import logging
from app.realtime.auth import get_redis
from app.realtime.server import sio
from app.realtime import constants as rc

logger = logging.getLogger(__name__)


async def register_sid(user_id: str, sid: str) -> list[str]:
    """ZADD the new sid; return list of sids to evict if cap exceeded."""
    r = get_redis()
    key = rc.KEY_PRESENCE_SIDS.format(user_id=user_id)
    score = time.time()
    await r.zadd(key, {sid: score})
    await r.expire(key, 7 * 24 * 3600)  # safety cap
    count = await r.zcard(key)
    to_evict = []
    if count > rc.MAX_DEVICES_PER_USER:
        # Lowest-score (oldest) members beyond the cap.
        excess = count - rc.MAX_DEVICES_PER_USER
        oldest = await r.zrange(key, 0, excess - 1)
        to_evict.extend(oldest)
        if oldest:
            await r.zrem(key, *oldest)
    return to_evict


async def unregister_sid(user_id: str, sid: str) -> int:
    r = get_redis()
    key = rc.KEY_PRESENCE_SIDS.format(user_id=user_id)
    await r.zrem(key, sid)
    return await r.zcard(key)


async def force_disconnect(sid: str, reason: str) -> None:
    try:
        await sio.emit(rc.EVT_FORCE_DISCONNECT, {"reason": reason}, to=sid)
        await sio.disconnect(sid)
    except Exception as exc:
        logger.warning("force_disconnect failed sid=%s reason=%s err=%s", sid, reason, exc)
```

- [ ] **Step 4: Wire into `connect` handler**

In `app/realtime/handlers.py`, append to the `connect` body just after `sio.enter_room(...)` and before the `connection:ready` emit:
```python
from app.realtime.presence import register_sid, force_disconnect
to_evict = await register_sid(user_id, sid)
for old_sid in to_evict:
    await force_disconnect(old_sid, rc.REASON_SUPERSEDED)
```

- [ ] **Step 5: Run, verify green**

```bash
pytest tests/realtime/test_multi_device.py -v
```
Expected: both PASS.

- [ ] **Step 6: Commit**

```bash
git add app/realtime/presence.py app/realtime/handlers.py tests/realtime/test_multi_device.py
git commit -m "feat(realtime): 3-device cap with sorted-set bookkeeping"
```

---

### Task 1.5: Disconnect handler + grace-period offline broadcast (TDD)

**Files:**
- Modify: `flame_backend/app/realtime/handlers.py`
- Modify: `flame_backend/app/realtime/presence.py`
- Create: `flame_backend/tests/realtime/test_disconnect.py`

- [ ] **Step 1: Write failing tests**

`tests/realtime/test_disconnect.py`:
```python
import pytest
import asyncio
from app.core.security import create_access_token
from app.realtime.auth import get_redis
from app.realtime import constants as rc


@pytest.mark.asyncio
async def test_disconnect_removes_sid_from_zset(make_socket_client, seed_user):
    user = await seed_user()
    token = create_access_token({"sub": str(user.id)})
    c = await make_socket_client(token)
    await c.receive(timeout=2)
    await c.disconnect()
    await asyncio.sleep(0.5)
    count = await get_redis().zcard(rc.KEY_PRESENCE_SIDS.format(user_id=str(user.id)))
    assert count == 0


@pytest.mark.asyncio
async def test_grace_period_then_offline(make_socket_client, seed_user, monkeypatch):
    # Override grace ttl to 1s for the test.
    monkeypatch.setattr(rc, "PRESENCE_GRACE_TTL", 1)
    user = await seed_user()
    token = create_access_token({"sub": str(user.id)})
    c = await make_socket_client(token)
    await c.receive(timeout=2)
    await c.disconnect()
    # Grace key should appear immediately, then expire.
    r = get_redis()
    key = rc.KEY_PRESENCE_PENDING_OFFLINE.format(user_id=str(user.id))
    assert await r.get(key) is not None
    await asyncio.sleep(1.5)
    assert await r.get(key) is None
```

- [ ] **Step 2: Run, verify red**

- [ ] **Step 3: Add disconnect handler**

In `app/realtime/handlers.py`:
```python
@sio.event
async def disconnect(sid: str):
    session = await sio.get_session(sid)
    user_id = session.get("user_id") if session else None
    if not user_id:
        return
    from app.realtime.presence import unregister_sid, mark_pending_offline, clear_typing_for_user
    remaining = await unregister_sid(user_id, sid)
    await clear_typing_for_user(user_id)
    if remaining == 0:
        await mark_pending_offline(user_id)
```

- [ ] **Step 4: Add `mark_pending_offline` and `clear_typing_for_user` stubs in `presence.py`**

```python
async def mark_pending_offline(user_id: str) -> None:
    r = get_redis()
    key = rc.KEY_PRESENCE_PENDING_OFFLINE.format(user_id=user_id)
    await r.set(key, "1", ex=rc.PRESENCE_GRACE_TTL)


async def clear_typing_for_user(user_id: str) -> None:
    """Remove all typing keys for this user via the secondary index."""
    r = get_redis()
    idx = rc.KEY_TYPING_INDEX.format(user_id=user_id)
    members = await r.smembers(idx)
    if members:
        pipe = r.pipeline()
        for m in members:
            pipe.delete(m)
        pipe.delete(idx)
        await pipe.execute()
```

- [ ] **Step 5: Run, verify green**

```bash
pytest tests/realtime/test_disconnect.py -v
```

- [ ] **Step 6: Commit**

```bash
git add app/realtime/handlers.py app/realtime/presence.py tests/realtime/test_disconnect.py
git commit -m "feat(realtime): disconnect cleanup with grace-period offline TTL"
```

---

# Section 2 — Auth lifecycle & lifecycle-events

### Task 2.1: Token-expiry asyncio task + cancellation on refresh (TDD)

**Files:**
- Create: `flame_backend/app/realtime/token_lifecycle.py`
- Modify: `flame_backend/app/realtime/handlers.py`
- Create: `flame_backend/tests/realtime/test_token_lifecycle.py`

- [ ] **Step 1: Write failing test**

```python
# tests/realtime/test_token_lifecycle.py
import pytest, asyncio, time
from app.core.security import create_access_token
from app.realtime import constants as rc


@pytest.mark.asyncio
async def test_token_expiring_event_fires_before_expiry(make_socket_client, seed_user, monkeypatch):
    monkeypatch.setattr(rc, "TOKEN_EXPIRY_LEAD", 1)  # fire 1s before expiry
    user = await seed_user()
    # Token expiring in 2s
    payload = {"sub": str(user.id)}
    token = create_access_token(payload, expires_minutes_override=None)  # use shortcut below
    # The above helper must allow a custom expiry; if not, monkeypatch ACCESS_TOKEN_EXPIRE_MINUTES
    # before token creation. Implementation may vary; below patches.
    from app.core.config import settings
    monkeypatch.setattr(settings, "ACCESS_TOKEN_EXPIRE_MINUTES", 1/30)  # ~2s
    token = create_access_token({"sub": str(user.id)})
    c = await make_socket_client(token)
    # First event is connection:ready
    ready = await c.receive(timeout=2)
    assert ready[0] == "connection:ready"
    # Then within ~1s we expect token_expiring
    evt = await c.receive(timeout=2.5)
    assert evt[0] == "auth:token_expiring"


@pytest.mark.asyncio
async def test_token_refreshed_cancels_old_timer(make_socket_client, seed_user, monkeypatch):
    monkeypatch.setattr(rc, "TOKEN_EXPIRY_LEAD", 1)
    from app.core.config import settings
    monkeypatch.setattr(settings, "ACCESS_TOKEN_EXPIRE_MINUTES", 1/30)
    user = await seed_user()
    token = create_access_token({"sub": str(user.id)})
    c = await make_socket_client(token)
    await c.receive(timeout=2)  # connection:ready
    new_token = create_access_token({"sub": str(user.id)})
    await c.emit("auth:token_refreshed", {"token": new_token})
    # The old token_expiring should not arrive within window of original expiry.
    # We allow new token's expiring event to arrive though.
    try:
        evt = await c.receive(timeout=1.0)
        # If we get an event, it's the new token's expiring (not the cancelled old one,
        # which would have a timestamp identical to original schedule).
        assert evt[0] in ("auth:token_expiring",)
    except asyncio.TimeoutError:
        pass  # also acceptable
```

- [ ] **Step 2: Run, verify red**

- [ ] **Step 3: Implement `token_lifecycle.py`**

```python
"""Per-socket token-expiry monitoring."""
import asyncio
import time
import logging
from app.core.security import decode_token
from app.realtime.server import sio
from app.realtime import constants as rc

logger = logging.getLogger(__name__)


async def schedule_token_expiry(sid: str, token_payload: dict) -> asyncio.Task:
    exp = int(token_payload.get("exp", 0))
    delay = max(0.0, exp - time.time() - rc.TOKEN_EXPIRY_LEAD)

    async def _fire():
        try:
            await asyncio.sleep(delay)
            await sio.emit(rc.EVT_AUTH_TOKEN_EXPIRING, {}, to=sid)
            # If client doesn't refresh within TOKEN_EXPIRY_LEAD, force expiry.
            await asyncio.sleep(rc.TOKEN_EXPIRY_LEAD)
            await sio.emit(rc.EVT_AUTH_TOKEN_EXPIRED, {}, to=sid)
            await sio.disconnect(sid)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.warning("token expiry monitor failed sid=%s err=%s", sid, exc)

    return asyncio.create_task(_fire())


async def reset_for_new_token(sid: str, new_payload: dict) -> None:
    session = await sio.get_session(sid)
    old_task: asyncio.Task | None = session.get("token_expiry_task") if session else None
    if old_task and not old_task.done():
        old_task.cancel()
    new_task = await schedule_token_expiry(sid, new_payload)
    session = session or {}
    session["token_expiry_task"] = new_task
    await sio.save_session(sid, session)
```

- [ ] **Step 4: Wire into `connect` and add `auth:token_refreshed` handler**

In `handlers.py`, modify `connect` to schedule the timer after `connection:ready`:
```python
from app.realtime.token_lifecycle import schedule_token_expiry, reset_for_new_token
from app.core.security import decode_token

# inside connect, after enter_room and emit:
payload = decode_token(auth["token"])
task = await schedule_token_expiry(sid, payload)
session = await sio.get_session(sid)
session["token_expiry_task"] = task
await sio.save_session(sid, session)


@sio.event
async def auth_token_refreshed(sid: str, data: dict):
    new_token = data.get("token")
    payload = decode_token(new_token) if new_token else None
    if not payload or payload.get("type") != "access":
        return  # ignore invalid refreshes; old timer will fire as scheduled
    await reset_for_new_token(sid, payload)
```

Note: Socket.IO event-name handler functions can't have `:` in their Python name. Register the colon-named event explicitly:
```python
sio.on("auth:token_refreshed", auth_token_refreshed)
```

- [ ] **Step 5: Verify**

```bash
pytest tests/realtime/test_token_lifecycle.py -v
```

- [ ] **Step 6: Commit**

```bash
git add app/realtime/token_lifecycle.py app/realtime/handlers.py tests/realtime/test_token_lifecycle.py
git commit -m "feat(realtime): token-expiry timer with cancellation on refresh"
```

---

### Task 2.2: Banned-user pub/sub channel for force-disconnect (TDD)

**Files:**
- Create: `flame_backend/app/realtime/ban_listener.py`
- Modify: `flame_backend/app/realtime/server.py`
- Create: `flame_backend/tests/realtime/test_banned.py`

- [ ] **Step 1: Failing test**

```python
# tests/realtime/test_banned.py
import pytest, asyncio
from app.core.security import create_access_token


@pytest.mark.asyncio
async def test_banned_pubsub_forces_disconnect(make_socket_client, seed_user):
    from app.realtime.auth import get_redis
    from app.realtime import constants as rc
    user = await seed_user()
    token = create_access_token({"sub": str(user.id)})
    c = await make_socket_client(token)
    await c.receive(timeout=2)
    await get_redis().publish(rc.CHAN_USER_BANNED, str(user.id))
    evt = await c.receive(timeout=2)
    assert evt[0] == "force_disconnect"
    assert evt[1]["reason"] == "banned"
```

- [ ] **Step 2: Run, verify red**

- [ ] **Step 3: Implement `ban_listener.py`**

```python
"""Subscribe to user:banned channel; force-disconnect all sids of banned users."""
import asyncio
import json
import logging
from app.realtime.auth import get_redis
from app.realtime.presence import force_disconnect
from app.realtime import constants as rc

logger = logging.getLogger(__name__)
_listener_task: asyncio.Task | None = None


async def start():
    global _listener_task
    if _listener_task and not _listener_task.done():
        return

    async def _run():
        r = get_redis()
        pubsub = r.pubsub()
        await pubsub.subscribe(rc.CHAN_USER_BANNED)
        try:
            async for msg in pubsub.listen():
                if msg["type"] != "message":
                    continue
                user_id = msg["data"]
                key = rc.KEY_PRESENCE_SIDS.format(user_id=user_id)
                sids = await r.zrange(key, 0, -1)
                for sid in sids:
                    await force_disconnect(sid, rc.REASON_BANNED)
                if sids:
                    await r.zrem(key, *sids)
        except asyncio.CancelledError:
            await pubsub.close()
            raise

    _listener_task = asyncio.create_task(_run())


async def stop():
    if _listener_task and not _listener_task.done():
        _listener_task.cancel()
        try:
            await _listener_task
        except asyncio.CancelledError:
            pass
```

- [ ] **Step 4: Start the listener on app startup**

In `app/main.py` lifespan, inside the `if getattr(settings, "CHAT_V2_ENABLED", False):` block (move the conditional up to startup if not there yet), add:
```python
from app.realtime import ban_listener
await ban_listener.start()
```
And on shutdown:
```python
await ban_listener.stop()
```

The test fixture imports `app.realtime.handlers` directly; explicitly start the listener in the fixture as well by adding to `tests/realtime/conftest.py`'s `app_with_realtime` after importing handlers:
```python
from app.realtime import ban_listener
await ban_listener.start()
```
And on teardown before `await close_mongo_connection()`:
```python
await ban_listener.stop()
```

- [ ] **Step 5: Run, verify green**

- [ ] **Step 6: Commit**

```bash
git add app/realtime/ban_listener.py app/main.py tests/realtime/conftest.py tests/realtime/test_banned.py
git commit -m "feat(realtime): user:banned pub/sub force-disconnects all sids"
```

---

### Task 2.3: Reaper task with leader election

**Files:**
- Create: `flame_backend/app/realtime/reaper.py`
- Modify: `flame_backend/app/main.py` (start/stop)
- Create: `flame_backend/tests/realtime/test_reaper.py`

- [ ] **Step 1: Failing test**

```python
# tests/realtime/test_reaper.py
import pytest, asyncio
from app.realtime.auth import get_redis
from app.realtime import constants as rc


@pytest.mark.asyncio
async def test_reaper_removes_orphan_sid(monkeypatch):
    from app.realtime import reaper
    monkeypatch.setattr(rc, "PING_TIMEOUT", 1)
    r = get_redis()
    fake_user = "user-reaper-x"
    fake_sid = "sid-orphan"
    key = rc.KEY_PRESENCE_SIDS.format(user_id=fake_user)
    # Score: 100s ago — definitely older than ping_timeout+30
    await r.zadd(key, {fake_sid: 100.0})
    await reaper.run_one_pass()
    members = await r.zrange(key, 0, -1)
    assert fake_sid not in members
    await r.delete(key)
```

- [ ] **Step 2: Run, verify red**

- [ ] **Step 3: Implement `reaper.py`**

```python
"""Periodically reap orphaned sids in presence:sids:* whose Socket.IO room
membership doesn't exist."""
import asyncio
import logging
import time
import uuid
from app.realtime.auth import get_redis
from app.realtime.server import sio
from app.realtime import constants as rc

logger = logging.getLogger(__name__)
_task: asyncio.Task | None = None
WORKER_ID = uuid.uuid4().hex


async def _try_acquire_lock() -> bool:
    r = get_redis()
    return bool(await r.set(rc.KEY_REAPER_LOCK, WORKER_ID, nx=True, ex=90))


async def _renew_lock() -> bool:
    r = get_redis()
    cur = await r.get(rc.KEY_REAPER_LOCK)
    if cur != WORKER_ID:
        return False
    await r.expire(rc.KEY_REAPER_LOCK, 90)
    return True


async def _release_lock() -> None:
    lua = (
        "if redis.call('get', KEYS[1]) == ARGV[1] then "
        "return redis.call('del', KEYS[1]) else return 0 end"
    )
    r = get_redis()
    await r.eval(lua, 1, rc.KEY_REAPER_LOCK, WORKER_ID)


async def run_one_pass() -> None:
    """Single sweep — used directly in tests."""
    r = get_redis()
    threshold = time.time() - (rc.PING_TIMEOUT + 30)
    cursor = 0
    while True:
        cursor, keys = await r.scan(cursor=cursor, match="presence:sids:*", count=200)
        for key in keys:
            user_id = key.split(":", 2)[-1]
            members = await r.zrange(key, 0, -1, withscores=True)
            live_sids = sio.manager.rooms.get("/", {}).get(f"user:{user_id}", set())
            stale = [m for (m, s) in members if s < threshold and m not in live_sids]
            if stale:
                await r.zrem(key, *stale)
        if cursor == 0:
            break


async def _loop():
    while True:
        try:
            if await _try_acquire_lock():
                try:
                    await run_one_pass()
                finally:
                    await _release_lock()
        except Exception as exc:
            logger.warning("reaper pass failed: %s", exc)
        await asyncio.sleep(60)


async def start():
    global _task
    if _task and not _task.done():
        return
    _task = asyncio.create_task(_loop())


async def stop():
    global _task
    if _task and not _task.done():
        _task.cancel()
        try:
            await _task
        except asyncio.CancelledError:
            pass
```

- [ ] **Step 4: Wire start/stop in `main.py` lifespan and test conftest**

Same pattern as ban_listener.

- [ ] **Step 5: Verify**

```bash
pytest tests/realtime/test_reaper.py -v
```

- [ ] **Step 6: Commit**

```bash
git add app/realtime/reaper.py app/main.py tests/realtime/conftest.py tests/realtime/test_reaper.py
git commit -m "feat(realtime): orphan-sid reaper with leader election"
```

---

# Section 3 — Backend message flow

### Task 3.1: Conversation schema migration script

**Files:**
- Create: `flame_backend/scripts/migrate_chat_v2.py`
- Modify: `flame_backend/app/models/conversation.py` (add `participants` field + `Participant` BaseModel)
- Create: `flame_backend/tests/realtime/test_migration_script.py`

- [ ] **Step 1: Add `Participant` and `participants` field to `Conversation`**

In `app/models/conversation.py`, after the `PinnedMessage` class:
```python
class Participant(BaseModel):
    user_id: str
    last_read_message_id: Optional[str] = None
    last_read_at: Optional[datetime] = None
    unread_count: int = 0
    joined_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
```

Inside `Conversation` (before `class Settings`):
```python
    # Phase 1 — per-user read state. Dual-written alongside user1_unread_count
    # / user2_unread_count during the transition; legacy fields removed in
    # Phase 2.
    participants: List[Participant] = Field(default_factory=list)
```

Update helper methods to also write to `participants`:
```python
    def increment_unread(self, for_user_id: str):
        if self.user1_id == for_user_id:
            self.user1_unread_count += 1
        else:
            self.user2_unread_count += 1
        for p in self.participants:
            if p.user_id == for_user_id:
                p.unread_count += 1

    def reset_unread(self, for_user_id: str):
        if self.user1_id == for_user_id:
            self.user1_unread_count = 0
        else:
            self.user2_unread_count = 0
        for p in self.participants:
            if p.user_id == for_user_id:
                p.unread_count = 0
```

- [ ] **Step 2: Failing test for the migration script**

`tests/realtime/test_migration_script.py`:
```python
import pytest
from datetime import datetime, timezone
from app.models.conversation import Conversation
from app.models.message import Message, MessageType, MessageStatus


@pytest.mark.asyncio
async def test_migration_populates_participants(app_with_realtime, seed_user):
    u1 = await seed_user()
    u2 = await seed_user()
    conv = Conversation(match_id=f"m-{u1.id}-{u2.id}",
                        user1_id=str(u1.id), user2_id=str(u2.id),
                        user1_unread_count=2, user2_unread_count=0)
    await conv.insert()
    msg = Message(conversation_id=str(conv.id), sender_id=str(u2.id),
                  type=MessageType.TEXT, content="hi", status=MessageStatus.READ,
                  timestamp=datetime.now(timezone.utc))
    await msg.insert()

    from scripts.migrate_chat_v2 import migrate
    await migrate()

    fresh = await Conversation.get(conv.id)
    assert len(fresh.participants) == 2
    p1 = next(p for p in fresh.participants if p.user_id == str(u1.id))
    p2 = next(p for p in fresh.participants if p.user_id == str(u2.id))
    assert p1.unread_count == 2
    assert p1.last_read_message_id == str(msg.id)
    assert p2.unread_count == 0


@pytest.mark.asyncio
async def test_migration_idempotent(app_with_realtime, seed_user):
    u1 = await seed_user()
    u2 = await seed_user()
    conv = Conversation(match_id=f"m-{u1.id}-{u2.id}",
                        user1_id=str(u1.id), user2_id=str(u2.id))
    await conv.insert()
    from scripts.migrate_chat_v2 import migrate
    await migrate()
    await migrate()  # second run is a no-op
    fresh = await Conversation.get(conv.id)
    assert len(fresh.participants) == 2
```

- [ ] **Step 3: Implement `scripts/migrate_chat_v2.py`**

```python
"""One-shot migration: populate Conversation.participants[] from legacy fields.

Idempotent: skips conversations that already have a non-empty participants list.
Run via:  python -m scripts.migrate_chat_v2
"""
import asyncio
import logging
from datetime import datetime, timezone

from app.core.database import connect_to_mongo, close_mongo_connection
from app.models.conversation import Conversation, Participant
from app.models.message import Message, MessageStatus

logger = logging.getLogger(__name__)
DELETED_USER_SENTINEL = "deleted_user"


async def _build_participant(conversation_id: str, user_id: str, peer_id: str,
                              unread: int, joined_at: datetime) -> Participant:
    last_read_msg = await Message.find_one(
        {"conversation_id": conversation_id, "sender_id": peer_id,
         "status": MessageStatus.READ},
        sort=[("timestamp", -1)],
    )
    return Participant(
        user_id=user_id,
        last_read_message_id=str(last_read_msg.id) if last_read_msg else None,
        last_read_at=last_read_msg.timestamp if last_read_msg else None,
        unread_count=unread,
        joined_at=joined_at,
    )


async def migrate() -> None:
    skipped = migrated = orphans = 0
    async for conv in Conversation.find_all():
        if conv.participants:
            skipped += 1
            continue
        if not conv.user1_id or not conv.user2_id:
            orphans += 1
            logger.warning("orphan conversation %s skipped", conv.id)
            continue
        joined = conv.created_at or datetime.now(timezone.utc)
        p1 = await _build_participant(str(conv.id), conv.user1_id, conv.user2_id,
                                      conv.user1_unread_count, joined)
        p2 = await _build_participant(str(conv.id), conv.user2_id, conv.user1_id,
                                      conv.user2_unread_count, joined)
        conv.participants = [p1, p2]
        await conv.save()
        migrated += 1
    logger.info("migration complete: migrated=%d skipped=%d orphans=%d",
                migrated, skipped, orphans)


async def main():
    logging.basicConfig(level=logging.INFO)
    await connect_to_mongo()
    try:
        await migrate()
    finally:
        await close_mongo_connection()


if __name__ == "__main__":
    asyncio.run(main())
```

Create `flame_backend/scripts/__init__.py` (empty) so the module is importable.

- [ ] **Step 4: Verify**

```bash
pytest tests/realtime/test_migration_script.py -v
```

- [ ] **Step 5: Run the script against local dev DB**

```bash
python -m scripts.migrate_chat_v2
```
Expected: log line `migration complete: migrated=N skipped=0 orphans=0`. Re-run; expected: `migrated=0 skipped=N`.

- [ ] **Step 6: Commit**

```bash
git add app/models/conversation.py scripts/migrate_chat_v2.py scripts/__init__.py tests/realtime/test_migration_script.py
git commit -m "feat(chat): Conversation.participants[] schema + migration script"
```

---

### Task 3.2: Idempotency cache module (TDD pure unit)

**Files:**
- Create: `flame_backend/app/realtime/idempotency.py`
- Create: `flame_backend/tests/realtime/test_idempotency.py`

- [ ] **Step 1: Failing test**

```python
# tests/realtime/test_idempotency.py
import pytest
from app.realtime.idempotency import store, lookup
from app.realtime.auth import get_redis


@pytest.mark.asyncio
async def test_store_then_lookup_returns_cached(app_with_realtime):
    await store("u1", "cmid-1", {"id": "m1", "ts": "2026-05-08T00:00:00Z"})
    found = await lookup("u1", "cmid-1")
    assert found == {"id": "m1", "ts": "2026-05-08T00:00:00Z"}


@pytest.mark.asyncio
async def test_lookup_miss_returns_none(app_with_realtime):
    found = await lookup("u1", "no-such-cmid")
    assert found is None
```

- [ ] **Step 2: Implement**

```python
# app/realtime/idempotency.py
"""Server-side idempotency for message:send keyed on (user_id, client_message_id)."""
import json
from app.realtime.auth import get_redis
from app.realtime import constants as rc


async def lookup(user_id: str, client_message_id: str) -> dict | None:
    r = get_redis()
    key = rc.KEY_IDEMPOTENCY.format(user_id=user_id, client_message_id=client_message_id)
    raw = await r.get(key)
    if not raw:
        return None
    return json.loads(raw)


async def store(user_id: str, client_message_id: str, payload: dict) -> None:
    r = get_redis()
    key = rc.KEY_IDEMPOTENCY.format(user_id=user_id, client_message_id=client_message_id)
    await r.set(key, json.dumps(payload), ex=rc.IDEMPOTENCY_TTL)
```

- [ ] **Step 3: Verify**

```bash
pytest tests/realtime/test_idempotency.py -v
```

- [ ] **Step 4: Commit**

```bash
git add app/realtime/idempotency.py tests/realtime/test_idempotency.py
git commit -m "feat(realtime): idempotency cache module"
```

---

### Task 3.3: Emitters module (replaces notify_*)

**Files:**
- Create: `flame_backend/app/realtime/emitters.py`

(No tests for this task in isolation — the emitters are exercised by the end-to-end tests in tasks 3.4 / 4.x.)

- [ ] **Step 1: Implement**

```python
# app/realtime/emitters.py
"""Server-to-client emit helpers. Replaces app/chat/websocket.py's notify_*."""
from app.realtime.server import sio
from app.realtime import constants as rc


def _user_room(user_id: str) -> str:
    return f"user:{user_id}"


async def emit_message_new(recipient_id: str, message: dict) -> None:
    await sio.emit(rc.EVT_MESSAGE_NEW, {"message": message}, room=_user_room(recipient_id))


async def emit_message_sent(sender_id: str, message: dict, skip_sid: str | None = None) -> None:
    kwargs = {"room": _user_room(sender_id)}
    if skip_sid:
        kwargs["skip_sid"] = skip_sid
    await sio.emit(rc.EVT_MESSAGE_SENT, {"message": message}, **kwargs)


async def emit_message_edited(recipient_id: str, message: dict) -> None:
    await sio.emit(rc.EVT_MESSAGE_EDITED, {"message": message}, room=_user_room(recipient_id))


async def emit_message_deleted(recipient_id: str, conversation_id: str, message_id: str) -> None:
    await sio.emit(
        rc.EVT_MESSAGE_DELETED,
        {"conversation_id": conversation_id, "message_id": message_id},
        room=_user_room(recipient_id),
    )


async def emit_reaction_update(recipient_id: str, conversation_id: str,
                                message_id: str, user_id: str, emoji: str | None,
                                action: str) -> None:
    await sio.emit(
        rc.EVT_REACTION_UPDATE,
        {"conversation_id": conversation_id, "message_id": message_id,
         "user_id": user_id, "emoji": emoji, "action": action},
        room=_user_room(recipient_id),
    )


async def emit_pin_update(recipient_id: str, conversation_id: str,
                           message_id: str, action: str, pinned_by: str | None) -> None:
    await sio.emit(
        rc.EVT_PIN_UPDATE,
        {"conversation_id": conversation_id, "message_id": message_id,
         "action": action, "pinned_by": pinned_by},
        room=_user_room(recipient_id),
    )


async def emit_match_new(user_id: str, match_data: dict) -> None:
    await sio.emit(rc.EVT_MATCH_NEW, match_data, room=_user_room(user_id))


async def emit_read_update(peer_id: str, conversation_id: str,
                            last_read_message_id: str, last_read_at_iso: str) -> None:
    await sio.emit(
        rc.EVT_READ_UPDATE,
        {"conversation_id": conversation_id,
         "last_read_message_id": last_read_message_id,
         "last_read_at": last_read_at_iso},
        room=_user_room(peer_id),
    )


async def emit_typing_update(peer_id: str, conversation_id: str,
                              user_id: str, is_typing: bool) -> None:
    await sio.emit(
        rc.EVT_TYPING_UPDATE,
        {"conversation_id": conversation_id, "user_id": user_id, "is_typing": is_typing},
        room=_user_room(peer_id),
    )


async def emit_presence_update(subscriber_id: str, user_id: str,
                                 is_online: bool, last_active_iso: str | None) -> None:
    await sio.emit(
        rc.EVT_PRESENCE_UPDATE,
        {"user_id": user_id, "is_online": is_online, "last_active": last_active_iso},
        room=_user_room(subscriber_id),
    )
```

- [ ] **Step 2: Smoke import**

```bash
python -c "from app.realtime import emitters; print(dir(emitters))"
```

- [ ] **Step 3: Commit**

```bash
git add app/realtime/emitters.py
git commit -m "feat(realtime): emitters module replacing notify_*"
```

---

### Task 3.4: `on_message_send` happy path + idempotency (TDD)

**Files:**
- Create: `flame_backend/app/realtime/queue.py`
- Modify: `flame_backend/app/realtime/handlers.py`
- Create: `flame_backend/tests/realtime/test_send.py`

- [ ] **Step 1: Failing tests**

```python
# tests/realtime/test_send.py
import pytest, asyncio, uuid
from app.core.security import create_access_token


@pytest.fixture
async def conversation_pair(app_with_realtime, seed_user):
    from app.models.conversation import Conversation, Participant
    u1 = await seed_user()
    u2 = await seed_user()
    conv = Conversation(
        match_id=f"m-{u1.id}-{u2.id}",
        user1_id=str(u1.id), user2_id=str(u2.id),
        participants=[
            Participant(user_id=str(u1.id)),
            Participant(user_id=str(u2.id)),
        ],
    )
    await conv.insert()
    return u1, u2, conv


@pytest.mark.asyncio
async def test_send_text_persists_and_acks(make_socket_client, conversation_pair):
    u1, u2, conv = conversation_pair
    t = create_access_token({"sub": str(u1.id)})
    c = await make_socket_client(t)
    await c.receive(timeout=2)  # ready

    cmid = str(uuid.uuid4())
    ack = await c.call("message:send", {
        "client_message_id": cmid,
        "conversation_id": str(conv.id),
        "type": "text",
        "content": "hello",
    }, timeout=3)
    assert ack["ok"] is True
    msg = ack["message"]
    assert msg["content"] == "hello"
    assert msg["sender_id"] == str(u1.id)
    from app.models.message import Message
    found = await Message.find_one({"client_message_id": cmid})
    assert found is not None


@pytest.mark.asyncio
async def test_send_idempotent_returns_same_id(make_socket_client, conversation_pair):
    u1, u2, conv = conversation_pair
    t = create_access_token({"sub": str(u1.id)})
    c = await make_socket_client(t)
    await c.receive(timeout=2)
    cmid = str(uuid.uuid4())
    payload = {"client_message_id": cmid, "conversation_id": str(conv.id),
               "type": "text", "content": "x"}
    a1 = await c.call("message:send", payload, timeout=3)
    a2 = await c.call("message:send", payload, timeout=3)
    assert a1["message"]["id"] == a2["message"]["id"]
    from app.models.message import Message
    count = await Message.find({"client_message_id": cmid}).count()
    assert count == 1


@pytest.mark.asyncio
async def test_recipient_receives_message_new(make_socket_client, conversation_pair):
    u1, u2, conv = conversation_pair
    t1 = create_access_token({"sub": str(u1.id)})
    t2 = create_access_token({"sub": str(u2.id)})
    s = await make_socket_client(t1)
    r = await make_socket_client(t2)
    await s.receive(timeout=2); await r.receive(timeout=2)

    await s.emit("message:send", {
        "client_message_id": str(uuid.uuid4()),
        "conversation_id": str(conv.id),
        "type": "text", "content": "hi"})
    evt = await r.receive(timeout=3)
    assert evt[0] == "message:new"
    assert evt[1]["message"]["content"] == "hi"
```

- [ ] **Step 2: Implement queue helper**

```python
# app/realtime/queue.py
"""Offline message queue. Used when recipient has no live sockets."""
import json
from app.realtime.auth import get_redis
from app.realtime import constants as rc


async def enqueue_for_offline(recipient_id: str, message: dict) -> None:
    r = get_redis()
    key = rc.KEY_OFFLINE_QUEUE.format(user_id=recipient_id)
    pipe = r.pipeline()
    pipe.lpush(key, json.dumps(message))
    pipe.ltrim(key, 0, rc.OFFLINE_QUEUE_CAP - 1)
    pipe.expire(key, rc.OFFLINE_QUEUE_TTL)
    await pipe.execute()


async def is_user_online(user_id: str) -> bool:
    r = get_redis()
    return await r.zcard(rc.KEY_PRESENCE_SIDS.format(user_id=user_id)) > 0
```

- [ ] **Step 3: Implement `message:send` handler**

In `handlers.py`:
```python
import re
import time
import uuid
from datetime import datetime, timezone
from app.realtime import idempotency, emitters
from app.realtime.queue import enqueue_for_offline, is_user_online
from app.realtime import constants as rc

_MEDIA_RE = re.compile(rc.MEDIA_URL_PATTERN)
_VALID_TYPES = {"text", "image", "video", "audio", "voice", "sticker", "gif"}


async def on_message_send(sid: str, data: dict) -> dict:
    session = await sio.get_session(sid)
    user_id = session.get("user_id") if session else None
    if not user_id:
        return {"ok": False, "error": {"code": "UNAUTHORIZED"}}

    # 1. Validate
    cmid = data.get("client_message_id")
    if not cmid or not isinstance(cmid, str) or len(cmid) > rc.CLIENT_MESSAGE_ID_CAP:
        return {"ok": False, "error": {"code": "VALIDATION", "message": "bad client_message_id"}}
    conversation_id = data.get("conversation_id")
    mtype = data.get("type")
    content = data.get("content") or ""
    media = data.get("media")
    if mtype not in _VALID_TYPES:
        return {"ok": False, "error": {"code": "VALIDATION", "message": "bad type"}}
    if mtype == "text" and (not content or len(content) > rc.CONTENT_LENGTH_CAP):
        return {"ok": False, "error": {"code": "VALIDATION", "message": "bad content"}}
    if mtype != "text" and (not media or not _MEDIA_RE.match(media.get("url", ""))):
        return {"ok": False, "error": {"code": "VALIDATION", "message": "bad media url"}}

    # 2. Idempotency
    cached = await idempotency.lookup(user_id, cmid)
    if cached:
        return {"ok": True, "message": cached}

    # 3. Authorization
    from app.models.conversation import Conversation
    conv = await Conversation.get(conversation_id)
    if not conv or user_id not in (conv.user1_id, conv.user2_id):
        return {"ok": False, "error": {"code": "FORBIDDEN"}}
    recipient_id = conv.get_other_user_id(user_id)

    # Check block (hot cache)
    import json
    raw = await get_redis().get(rc.KEY_USER_HOT.format(user_id=recipient_id))
    if raw:
        peer_hot = json.loads(raw)
        if user_id in peer_hot.get("blocked_users", []):
            return {"ok": False, "error": {"code": "BLOCKED"}}

    # 4. Persist
    from app.models.message import Message, MessageType
    now = datetime.now(timezone.utc)
    msg = Message(
        conversation_id=conversation_id,
        sender_id=user_id,
        type=MessageType(mtype),
        content=content,
        client_message_id=cmid,
        timestamp=now,
        media=media,
        reply_to_message_id=data.get("reply_to_message_id"),
    )
    await msg.insert()

    canonical = {
        "id": str(msg.id),
        "conversation_id": conversation_id,
        "sender_id": user_id,
        "type": mtype,
        "content": content,
        "media": media,
        "client_message_id": cmid,
        "server_timestamp": now.isoformat(),
        "reply_to_message_id": data.get("reply_to_message_id"),
    }

    # 5. Idempotency cache
    await idempotency.store(user_id, cmid, canonical)

    # 6. Schedule async post-send (does not block ack)
    import asyncio
    asyncio.create_task(_post_send(conv, recipient_id, user_id, sid, canonical))

    # 7. Ack
    return {"ok": True, "message": canonical}


async def _post_send(conv, recipient_id: str, sender_id: str, sender_sid: str, canonical: dict) -> None:
    try:
        # Update conversation last_message_* and unread
        conv.last_message_id = canonical["id"]
        conv.last_message_content = canonical["content"]
        conv.last_message_sender_id = sender_id
        from datetime import datetime
        conv.last_message_at = datetime.fromisoformat(canonical["server_timestamp"])
        conv.increment_unread(recipient_id)
        await conv.save()
    except Exception:
        pass

    # Broadcast new + mirror sent
    if await is_user_online(recipient_id):
        await emitters.emit_message_new(recipient_id, canonical)
    else:
        await enqueue_for_offline(recipient_id, canonical)
    await emitters.emit_message_sent(sender_id, canonical, skip_sid=sender_sid)


sio.on(rc.EVT_MESSAGE_SEND, on_message_send)
```

- [ ] **Step 4: Add `client_message_id` and `media` fields to `Message` model if not present**

In `app/models/message.py`, add to the `Message` class (alongside existing fields):
```python
    client_message_id: Optional[str] = None
    media: Optional[dict] = None
```
And add an index:
```python
        # Inside Settings.indexes list:
        [("client_message_id", 1)],
```

- [ ] **Step 5: Verify**

```bash
pytest tests/realtime/test_send.py -v
```

- [ ] **Step 6: Commit**

```bash
git add app/realtime/queue.py app/realtime/handlers.py app/models/message.py tests/realtime/test_send.py
git commit -m "feat(realtime): message:send with idempotency + offline queue"
```

---

### Task 3.5: Mirror echo skip + offline queue drain on reconnect (TDD)

**Files:**
- Modify: `flame_backend/app/realtime/handlers.py` (drain on connect)
- Create: `flame_backend/tests/realtime/test_mirror_echo.py`
- Create: `flame_backend/tests/realtime/test_offline_drain.py`

- [ ] **Step 1: Failing tests**

```python
# tests/realtime/test_mirror_echo.py
import pytest, asyncio, uuid
from app.core.security import create_access_token


@pytest.mark.asyncio
async def test_originator_does_not_receive_message_sent(make_socket_client, conversation_pair):
    u1, _, conv = conversation_pair
    t = create_access_token({"sub": str(u1.id)})
    c1 = await make_socket_client(t, "d1")
    c2 = await make_socket_client(t, "d2")
    await c1.receive(timeout=2); await c2.receive(timeout=2)

    cmid = str(uuid.uuid4())
    await c1.emit("message:send", {"client_message_id": cmid,
        "conversation_id": str(conv.id), "type": "text", "content": "x"})

    # c2 should receive message:sent
    evt2 = await c2.receive(timeout=3)
    assert evt2[0] == "message:sent"
    # c1 should NOT receive message:sent (only its ack)
    with pytest.raises(asyncio.TimeoutError):
        await c1.receive(timeout=1.5)
```

```python
# tests/realtime/test_offline_drain.py
import pytest, asyncio, uuid
from app.core.security import create_access_token


@pytest.mark.asyncio
async def test_recipient_receives_queued_messages_on_connect(make_socket_client, conversation_pair):
    u1, u2, conv = conversation_pair
    ts1 = create_access_token({"sub": str(u1.id)})
    s = await make_socket_client(ts1)
    await s.receive(timeout=2)
    # Send 2 messages while u2 is offline
    for _ in range(2):
        await s.emit("message:send", {"client_message_id": str(uuid.uuid4()),
            "conversation_id": str(conv.id), "type": "text", "content": "x"})
    await asyncio.sleep(0.5)
    # u2 connects
    ts2 = create_access_token({"sub": str(u2.id)})
    r = await make_socket_client(ts2)
    await r.receive(timeout=2)  # ready
    received = []
    while len(received) < 2:
        evt = await r.receive(timeout=2)
        if evt[0] == "message:new":
            received.append(evt)
    assert len(received) == 2
```

- [ ] **Step 2: Implement drain on connect**

In `handlers.py` `connect`, after emitting `connection:ready`, add:
```python
asyncio.create_task(_drain_offline(user_id, sid))
```
And implement:
```python
async def _drain_offline(user_id: str, sid: str) -> None:
    import json
    r = get_redis()
    lock_key = rc.KEY_QUEUE_LOCK.format(user_id=user_id)
    if not await r.set(lock_key, sid, nx=True, ex=5):
        return  # another sid is draining
    try:
        key = rc.KEY_OFFLINE_QUEUE.format(user_id=user_id)
        # RPOP one at a time so we replay oldest-first (LPUSH+LTRIM keeps newest at head)
        while True:
            raw = await r.rpop(key)
            if raw is None:
                break
            msg = json.loads(raw)
            await emitters.emit_message_new(user_id, msg)
    finally:
        await r.delete(lock_key)
```

(Mirror echo `skip_sid` is already implemented in Task 3.4.)

- [ ] **Step 3: Verify**

```bash
pytest tests/realtime/test_mirror_echo.py tests/realtime/test_offline_drain.py -v
```

- [ ] **Step 4: Commit**

```bash
git add app/realtime/handlers.py tests/realtime/test_mirror_echo.py tests/realtime/test_offline_drain.py
git commit -m "feat(realtime): mirror echo skip and offline queue drain on connect"
```

---

# Section 4 — Read receipts, typing, presence

### Task 4.1: Read receipts with monotonic conditional write (TDD)

**Files:**
- Modify: `flame_backend/app/realtime/handlers.py`
- Create: `flame_backend/tests/realtime/test_read_receipts.py`

- [ ] **Step 1: Failing test**

```python
# tests/realtime/test_read_receipts.py
import pytest, asyncio, uuid
from app.core.security import create_access_token
from app.models.message import Message
from app.models.conversation import Conversation


@pytest.mark.asyncio
async def test_message_read_advances_last_read(make_socket_client, conversation_pair):
    u1, u2, conv = conversation_pair
    s = await make_socket_client(create_access_token({"sub": str(u1.id)}))
    r = await make_socket_client(create_access_token({"sub": str(u2.id)}))
    await s.receive(timeout=2); await r.receive(timeout=2)
    ack = await s.call("message:send", {"client_message_id": str(uuid.uuid4()),
        "conversation_id": str(conv.id), "type": "text", "content": "x"}, timeout=3)
    msg_id = ack["message"]["id"]
    await r.receive(timeout=3)  # message:new

    await r.emit("message:read", {"conversation_id": str(conv.id),
                                  "last_read_message_id": msg_id})
    # Sender receives read:update
    evt = await s.receive(timeout=3)
    assert evt[0] == "read:update"
    assert evt[1]["last_read_message_id"] == msg_id


@pytest.mark.asyncio
async def test_read_monotonic(make_socket_client, conversation_pair):
    u1, u2, conv = conversation_pair
    s = await make_socket_client(create_access_token({"sub": str(u1.id)}))
    r = await make_socket_client(create_access_token({"sub": str(u2.id)}))
    await s.receive(timeout=2); await r.receive(timeout=2)
    ack1 = await s.call("message:send", {"client_message_id": str(uuid.uuid4()),
        "conversation_id": str(conv.id), "type": "text", "content": "1"}, timeout=3)
    ack2 = await s.call("message:send", {"client_message_id": str(uuid.uuid4()),
        "conversation_id": str(conv.id), "type": "text", "content": "2"}, timeout=3)
    # Drain inbound
    while True:
        try: await r.receive(timeout=0.3)
        except asyncio.TimeoutError: break

    # Mark up to ack2 first
    await r.emit("message:read", {"conversation_id": str(conv.id),
                                  "last_read_message_id": ack2["message"]["id"]})
    await asyncio.sleep(0.5)
    # Then a stale earlier mark
    await r.emit("message:read", {"conversation_id": str(conv.id),
                                  "last_read_message_id": ack1["message"]["id"]})
    await asyncio.sleep(0.5)
    fresh = await Conversation.get(conv.id)
    me = next(p for p in fresh.participants if p.user_id == str(u2.id))
    assert me.last_read_message_id == ack2["message"]["id"]
```

- [ ] **Step 2: Implement `message:read` handler**

In `handlers.py`:
```python
from bson import ObjectId
from datetime import datetime, timezone


async def on_message_read(sid: str, data: dict):
    session = await sio.get_session(sid)
    user_id = session.get("user_id") if session else None
    if not user_id:
        return
    conv_id = data.get("conversation_id")
    last_id = data.get("last_read_message_id")
    if not conv_id or not last_id:
        return

    from app.models.conversation import Conversation
    coll = Conversation.get_motor_collection()
    now = datetime.now(timezone.utc)
    result = await coll.update_one(
        {
            "_id": ObjectId(conv_id),
            "participants": {
                "$elemMatch": {
                    "user_id": user_id,
                    "$or": [
                        {"last_read_message_id": None},
                        {"last_read_message_id": {"$lt": last_id}},
                    ],
                }
            },
        },
        {
            "$set": {
                "participants.$[me].last_read_message_id": last_id,
                "participants.$[me].last_read_at": now,
                "participants.$[me].unread_count": 0,
            }
        },
        array_filters=[{"me.user_id": user_id}],
    )
    if result.modified_count != 1:
        return  # out-of-order or no-op

    # Find peer to broadcast to
    conv = await Conversation.get(conv_id)
    peer_id = conv.get_other_user_id(user_id)
    await emitters.emit_read_update(peer_id, conv_id, last_id, now.isoformat())


sio.on(rc.EVT_MESSAGE_READ, on_message_read)
```

- [ ] **Step 3: Verify**

```bash
pytest tests/realtime/test_read_receipts.py -v
```

- [ ] **Step 4: Commit**

```bash
git add app/realtime/handlers.py tests/realtime/test_read_receipts.py
git commit -m "feat(realtime): monotonic last_read_message_id with read:update broadcast"
```

---

### Task 4.2: Typing indicator + secondary index cleanup (TDD)

**Files:**
- Modify: `flame_backend/app/realtime/handlers.py`
- Create: `flame_backend/tests/realtime/test_typing.py`

- [ ] **Step 1: Failing tests**

```python
# tests/realtime/test_typing.py
import pytest, asyncio
from app.core.security import create_access_token


@pytest.mark.asyncio
async def test_typing_start_broadcasts(make_socket_client, conversation_pair):
    u1, u2, conv = conversation_pair
    s = await make_socket_client(create_access_token({"sub": str(u1.id)}))
    r = await make_socket_client(create_access_token({"sub": str(u2.id)}))
    await s.receive(timeout=2); await r.receive(timeout=2)
    await s.emit("typing:start", {"conversation_id": str(conv.id)})
    evt = await r.receive(timeout=2)
    assert evt[0] == "typing:update"
    assert evt[1]["is_typing"] is True


@pytest.mark.asyncio
async def test_typing_cleared_on_disconnect(make_socket_client, conversation_pair):
    u1, u2, conv = conversation_pair
    s = await make_socket_client(create_access_token({"sub": str(u1.id)}))
    r = await make_socket_client(create_access_token({"sub": str(u2.id)}))
    await s.receive(timeout=2); await r.receive(timeout=2)
    await s.emit("typing:start", {"conversation_id": str(conv.id)})
    await r.receive(timeout=2)  # is_typing: true
    await s.disconnect()
    evt = await r.receive(timeout=2)
    assert evt[0] == "typing:update"
    assert evt[1]["is_typing"] is False
```

- [ ] **Step 2: Implement**

In `handlers.py`:
```python
async def on_typing_start(sid: str, data: dict):
    session = await sio.get_session(sid)
    user_id = session.get("user_id") if session else None
    conv_id = data.get("conversation_id")
    if not user_id or not conv_id:
        return
    from app.models.conversation import Conversation
    conv = await Conversation.get(conv_id)
    if not conv or user_id not in (conv.user1_id, conv.user2_id):
        return
    peer_id = conv.get_other_user_id(user_id)
    r = get_redis()
    key = rc.KEY_TYPING.format(conversation_id=conv_id, user_id=user_id)
    idx = rc.KEY_TYPING_INDEX.format(user_id=user_id)
    pipe = r.pipeline()
    pipe.set(key, peer_id, ex=rc.TYPING_KEY_TTL)
    pipe.sadd(idx, key)
    pipe.expire(idx, rc.TYPING_KEY_TTL * 4)
    await pipe.execute()
    await emitters.emit_typing_update(peer_id, conv_id, user_id, True)


async def on_typing_stop(sid: str, data: dict):
    session = await sio.get_session(sid)
    user_id = session.get("user_id") if session else None
    conv_id = data.get("conversation_id")
    if not user_id or not conv_id:
        return
    from app.models.conversation import Conversation
    conv = await Conversation.get(conv_id)
    if not conv:
        return
    peer_id = conv.get_other_user_id(user_id)
    r = get_redis()
    key = rc.KEY_TYPING.format(conversation_id=conv_id, user_id=user_id)
    idx = rc.KEY_TYPING_INDEX.format(user_id=user_id)
    pipe = r.pipeline()
    pipe.delete(key)
    pipe.srem(idx, key)
    await pipe.execute()
    await emitters.emit_typing_update(peer_id, conv_id, user_id, False)


sio.on(rc.EVT_TYPING_START, on_typing_start)
sio.on(rc.EVT_TYPING_STOP, on_typing_stop)
```

- [ ] **Step 3: Wire `clear_typing_for_user` to broadcast stops**

Update `presence.clear_typing_for_user` to broadcast `is_typing: false` to each peer before deleting:
```python
async def clear_typing_for_user(user_id: str) -> None:
    r = get_redis()
    idx = rc.KEY_TYPING_INDEX.format(user_id=user_id)
    members = await r.smembers(idx)
    if not members:
        return
    # Each member key is "typing:{conversation_id}:{user_id}"
    from app.realtime import emitters
    pipe = r.pipeline()
    for key in members:
        peer_id = await r.get(key)
        if peer_id:
            parts = key.split(":")
            conv_id = parts[1]
            await emitters.emit_typing_update(peer_id, conv_id, user_id, False)
        pipe.delete(key)
    pipe.delete(idx)
    await pipe.execute()
```

- [ ] **Step 4: Verify**

```bash
pytest tests/realtime/test_typing.py -v
```

- [ ] **Step 5: Commit**

```bash
git add app/realtime/handlers.py app/realtime/presence.py tests/realtime/test_typing.py
git commit -m "feat(realtime): typing indicator with secondary-index cleanup"
```

---

### Task 4.3: Presence subscriptions (TDD)

**Files:**
- Modify: `flame_backend/app/realtime/handlers.py`
- Modify: `flame_backend/app/realtime/presence.py`
- Create: `flame_backend/tests/realtime/test_presence.py`

- [ ] **Step 1: Failing test**

```python
# tests/realtime/test_presence.py
import pytest, asyncio
from app.core.security import create_access_token


@pytest.mark.asyncio
async def test_presence_subscribe_receives_online_event(make_socket_client, seed_user):
    u1 = await seed_user()
    u2 = await seed_user()
    c1 = await make_socket_client(create_access_token({"sub": str(u1.id)}))
    await c1.receive(timeout=2)
    await c1.emit("presence:subscribe", {"user_ids": [str(u2.id)]})
    await asyncio.sleep(0.2)
    # u2 connects → c1 should receive presence:update
    c2 = await make_socket_client(create_access_token({"sub": str(u2.id)}))
    await c2.receive(timeout=2)
    evt = await c1.receive(timeout=2)
    assert evt[0] == "presence:update"
    assert evt[1]["user_id"] == str(u2.id)
    assert evt[1]["is_online"] is True
```

- [ ] **Step 2: Implement**

Add to `presence.py`:
```python
async def add_subscriber(target_user_id: str, subscriber_id: str) -> None:
    r = get_redis()
    await r.sadd(rc.KEY_PRESENCE_SUBSCRIBERS.format(user_id=target_user_id), subscriber_id)
    await r.expire(rc.KEY_PRESENCE_SUBSCRIBERS.format(user_id=target_user_id), 7 * 24 * 3600)


async def get_subscribers(target_user_id: str) -> list[str]:
    r = get_redis()
    return list(await r.smembers(rc.KEY_PRESENCE_SUBSCRIBERS.format(user_id=target_user_id)))


async def broadcast_presence_change(user_id: str, is_online: bool, last_active_iso: str | None) -> None:
    from app.realtime import emitters
    subs = await get_subscribers(user_id)
    for sub in subs:
        await emitters.emit_presence_update(sub, user_id, is_online, last_active_iso)
```

In `handlers.py`:
```python
async def on_presence_subscribe(sid: str, data: dict):
    session = await sio.get_session(sid)
    user_id = session.get("user_id") if session else None
    if not user_id:
        return
    from app.realtime.presence import add_subscriber
    for target in data.get("user_ids", []):
        await add_subscriber(target, user_id)


sio.on(rc.EVT_PRESENCE_SUBSCRIBE, on_presence_subscribe)
```

In `connect` handler, after `connection:ready` emit, broadcast presence change:
```python
from app.realtime.presence import broadcast_presence_change
asyncio.create_task(broadcast_presence_change(user_id, True, None))
```

In `disconnect` handler, when `remaining == 0` and after grace expires (the keyspace-notification-driven offline broadcast — for now in dev we approximate by broadcasting at disconnect time):
```python
if remaining == 0:
    await mark_pending_offline(user_id)
    asyncio.create_task(_grace_offline_broadcast(user_id))
```
With:
```python
async def _grace_offline_broadcast(user_id: str) -> None:
    await asyncio.sleep(rc.PRESENCE_GRACE_TTL + 0.5)
    if not await is_user_online(user_id):
        from datetime import datetime, timezone
        await broadcast_presence_change(user_id, False, datetime.now(timezone.utc).isoformat())
```

(Note: this in-process fallback is dev-only per spec. Production keyspace-notifications path is added in a follow-up task if/when the operator confirms.)

- [ ] **Step 3: Verify**

- [ ] **Step 4: Commit**

```bash
git add app/realtime/handlers.py app/realtime/presence.py tests/realtime/test_presence.py
git commit -m "feat(realtime): presence subscribe + change broadcast"
```

---

### Task 4.4: Migrate existing `notify_*` call sites; delete `app/chat/websocket.py`

**Files:**
- Modify: `flame_backend/app/chat/routes.py` (replace notify_* imports/calls)
- Modify: `flame_backend/app/chat/service.py`
- Modify: `flame_backend/app/community/routes.py:353,417`
- Delete: `flame_backend/app/chat/websocket.py`
- Modify: `flame_backend/app/main.py` (remove `from app.chat.websocket import router as ws_router` and `app.include_router(ws_router)`)
- Modify: `flame_backend/app/core/redis.py` (remove `RedisPubSub` and `redis_pubsub` singleton; keep file as connection helper)

- [ ] **Step 1: List all callers and the migration mapping**

```bash
cd /Users/davis/Desktop/Personal/flame_backend
grep -rn "from app.chat.websocket import" app/
grep -rn "redis_pubsub" app/
grep -rn "notify_new_message\|notify_message_edited\|notify_message_deleted\|notify_reaction_added\|notify_reaction_removed\|notify_message_pinned\|notify_message_unpinned\|notify_new_match\|notify_user_online" app/
```
The migration table is in the spec. Each call site swaps to `from app.realtime import emitters` and the matching `emit_*` function.

- [ ] **Step 2: Update each caller**

Example (apply analogously to all):
```python
# Old
from app.chat.websocket import notify_new_message
await notify_new_message(conv_id, msg_dict, sender_id)

# New
from app.realtime import emitters
await emitters.emit_message_new(recipient_id, msg_dict)
```

For `notify_new_match` in `app/community/routes.py:353,417`:
```python
from app.realtime import emitters
await emitters.emit_match_new(data.user_id, match_data)
# (Conversation subscription was a Redis-pubsub-only concept that
# the new architecture handles via room joining at connect time.
# The 2nd publish to subscribe_conversation is dropped.)
```

For `notify_message_edited`/`deleted`/`reaction_*`/`pin_*`: each call site needs to know `recipient_id`. The legacy code computed it from the conversation; do the same lookup:
```python
from app.models.conversation import Conversation
conv = await Conversation.get(conversation_id)
recipient_id = conv.get_other_user_id(actor_id)
await emitters.emit_message_edited(recipient_id, msg_dict)
```

- [ ] **Step 3: Strip `app/chat/websocket.py` imports from `main.py`**

Remove these lines:
```python
from app.chat.websocket import router as ws_router
# ...
app.include_router(ws_router)
```
Also remove `from app.chat.websocket import handle_redis_message` and any `redis_pubsub` usage in the lifespan — the new realtime layer initializes itself via `build_asgi_app`.

- [ ] **Step 4: Delete `app/chat/websocket.py`**

```bash
git rm app/chat/websocket.py
```

- [ ] **Step 5: Strip `RedisPubSub` and `redis_pubsub` from `app/core/redis.py`**

Edit `app/core/redis.py` to keep only the `aioredis.from_url` connection helper (if any other module uses it). Remove the class `RedisPubSub`, the `redis_pubsub = RedisPubSub()` singleton, and any `print` statements (the spec mandated their removal).

- [ ] **Step 6: Verify backend smoke**

```bash
pytest tests/realtime/ -v
CHAT_V2_ENABLED=true uvicorn app.main:asgi_app --host 0.0.0.0 --port 8000 &
sleep 2
curl -s http://localhost:8000/health
kill %1
```
Expected: tests still pass; server still boots.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(chat): migrate notify_* to emitters; delete legacy websocket.py"
```

---

# Section 5 — Media uploads + rollout plumbing

### Task 5.1: Bucket public-read policy + CORS (operator action with verification)

**Files:** none (DigitalOcean Spaces console / s3cmd)

- [ ] **Step 1: Apply bucket policy granting public-read on the flame_backend prefix**

Use `s3cmd` against DO Spaces, or the DO control panel. Policy JSON:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadFlamePrefix",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::my-projects-media/flame_backend/*"
    }
  ]
}
```
Apply via:
```bash
s3cmd setpolicy /tmp/flame-bucket-policy.json s3://my-projects-media \
  --host=sfo3.digitaloceanspaces.com --host-bucket=%(bucket)s.sfo3.digitaloceanspaces.com
```

- [ ] **Step 2: Apply CORS allowing PUT from app origins**

```xml
<CORSConfiguration>
  <CORSRule>
    <AllowedOrigin>*</AllowedOrigin>
    <AllowedMethod>PUT</AllowedMethod>
    <AllowedMethod>GET</AllowedMethod>
    <AllowedHeader>*</AllowedHeader>
    <MaxAgeSeconds>3600</MaxAgeSeconds>
  </CORSRule>
</CORSConfiguration>
```
Apply via the control panel or `s3cmd setcors`.

- [ ] **Step 3: Verify**

```bash
curl -i -X OPTIONS https://my-projects-media.sfo3.digitaloceanspaces.com/ \
  -H "Origin: https://flame.banatalk.com" \
  -H "Access-Control-Request-Method: PUT"
```
Expected: 200 with `Access-Control-Allow-Methods: PUT` in the response.

- [ ] **Step 4: Document the action**

Append to `flame_backend/docs/operator-runbook.md` (create if needed):
```
## DO Spaces config (Phase 1)

- Bucket policy: public-read on flame_backend/* prefix.
- CORS: PUT allowed from any origin (tighten before public launch).
```

- [ ] **Step 5: Commit the runbook only (operator actions are out-of-tree)**

```bash
git add docs/operator-runbook.md
git commit -m "docs: operator runbook for Spaces public-read + CORS"
```

---

### Task 5.2: `POST /media/presign` endpoint (TDD)

**Files:**
- Create: `flame_backend/app/media/__init__.py`
- Create: `flame_backend/app/media/routes.py`
- Modify: `flame_backend/app/main.py` (include router)
- Create: `flame_backend/tests/realtime/test_presign.py`

- [ ] **Step 1: Failing test**

```python
# tests/realtime/test_presign.py
import pytest
import httpx
from app.core.security import create_access_token


@pytest.mark.asyncio
async def test_presign_returns_put_url(app_with_realtime, seed_user):
    user = await seed_user()
    t = create_access_token({"sub": str(user.id)})
    async with httpx.AsyncClient(base_url=app_with_realtime["url"]) as client:
        resp = await client.post("/v1/media/presign",
            json={"type": "image", "mime": "image/jpeg", "size_bytes": 100_000},
            headers={"Authorization": f"Bearer {t}"})
    assert resp.status_code == 200
    body = resp.json()
    assert "upload_url" in body
    assert "public_url" in body
    assert body["required_headers"]["Content-Type"] == "image/jpeg"


@pytest.mark.asyncio
async def test_presign_rejects_oversize(app_with_realtime, seed_user):
    user = await seed_user()
    t = create_access_token({"sub": str(user.id)})
    async with httpx.AsyncClient(base_url=app_with_realtime["url"]) as client:
        resp = await client.post("/v1/media/presign",
            json={"type": "image", "mime": "image/jpeg", "size_bytes": 50_000_000},
            headers={"Authorization": f"Bearer {t}"})
    assert resp.status_code == 400
```

(Add a FastAPI `app` to the fixture so tests can hit REST.)

- [ ] **Step 2: Implement**

```python
# app/media/routes.py
import uuid
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.core.dependencies import get_current_user
from app.core.storage import storage
from app.core.config import settings
from app.models.user import User

router = APIRouter(prefix="/media", tags=["media"])

MAX_BYTES = {"image": 10_000_000, "video": 50_000_000, "audio": 20_000_000, "voice": 5_000_000}
ALLOWED_MIME = {
    "image": {"image/jpeg", "image/png", "image/webp"},
    "video": {"video/mp4", "video/quicktime"},
    "audio": {"audio/mpeg", "audio/aac", "audio/mp4"},
    "voice": {"audio/mp4", "audio/aac"},
}
EXT = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp",
       "video/mp4": "mp4", "video/quicktime": "mov",
       "audio/mpeg": "mp3", "audio/aac": "aac", "audio/mp4": "m4a"}


class PresignReq(BaseModel):
    type: str = Field(pattern=r"^(image|video|audio|voice)$")
    mime: str
    size_bytes: int = Field(gt=0)
    duration_ms: int | None = None


class PresignResp(BaseModel):
    upload_url: str
    public_url: str
    required_headers: dict


@router.post("/presign", response_model=PresignResp)
async def presign(req: PresignReq, user: User = Depends(get_current_user)):
    if req.size_bytes > MAX_BYTES[req.type]:
        raise HTTPException(400, "size too large")
    if req.mime not in ALLOWED_MIME[req.type]:
        raise HTTPException(400, "mime not allowed")
    ext = EXT.get(req.mime, "bin")
    key = f"{settings.SPACES_PROJECT_FOLDER}/{req.type}/{user.id}/{uuid.uuid4().hex}.{ext}"
    upload_url = storage.client.generate_presigned_url(
        "put_object",
        Params={"Bucket": settings.SPACES_BUCKET, "Key": key, "ContentType": req.mime},
        ExpiresIn=300,
    )
    public_url = f"{settings.SPACES_CDN_URL}/{key}"
    return PresignResp(
        upload_url=upload_url,
        public_url=public_url,
        required_headers={"Content-Type": req.mime, "Content-Length": str(req.size_bytes)},
    )
```

In `app/main.py`:
```python
from app.media.routes import router as media_router
app.include_router(media_router, prefix=settings.API_V1_PREFIX)
```

- [ ] **Step 3: Update `app_with_realtime` fixture to include the FastAPI router**

In `tests/realtime/conftest.py`, replace `fastapi_app = FastAPI()` with:
```python
from app.main import app as fastapi_app
```

- [ ] **Step 4: Verify**

```bash
pytest tests/realtime/test_presign.py -v
```

- [ ] **Step 5: Commit**

```bash
git add app/media/ app/main.py tests/realtime/conftest.py tests/realtime/test_presign.py
git commit -m "feat(media): POST /media/presign for direct PUT to Spaces"
```

---

### Task 5.3: `GET /media/gif/search` Tenor proxy (TDD)

**Files:**
- Modify: `flame_backend/app/media/routes.py`
- Create: `flame_backend/tests/realtime/test_gif_search.py`

- [ ] **Step 1: Failing test (mocked Tenor)**

```python
# tests/realtime/test_gif_search.py
import pytest, httpx
from app.core.security import create_access_token


@pytest.mark.asyncio
async def test_gif_search_returns_results(app_with_realtime, seed_user, monkeypatch):
    async def fake_get(self, url, *args, **kwargs):
        class R:
            status_code = 200
            def json(self):
                return {"results": [{"id": "1", "media_formats": {
                    "tinygif": {"url": "https://media.tenor.com/foo.gif",
                                "dims": [120, 90]}}}]}
        return R()
    monkeypatch.setattr(httpx.AsyncClient, "get", fake_get)

    user = await seed_user()
    t = create_access_token({"sub": str(user.id)})
    async with httpx.AsyncClient(base_url=app_with_realtime["url"]) as client:
        resp = await client.get("/v1/media/gif/search?q=cat&limit=5",
                                headers={"Authorization": f"Bearer {t}"})
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["results"]) == 1
    assert body["results"][0]["url"].startswith("https://media.tenor.com/")
```

- [ ] **Step 2: Implement**

```python
# Append to app/media/routes.py
import httpx

@router.get("/gif/search")
async def gif_search(q: str, limit: int = 20, user: User = Depends(get_current_user)):
    if limit > 50:
        limit = 50
    url = "https://tenor.googleapis.com/v2/search"
    params = {"q": q, "limit": limit, "media_filter": "tinygif", "client_key": "flame"}
    async with httpx.AsyncClient(timeout=5.0) as client:
        resp = await client.get(url, params=params)
    if resp.status_code != 200:
        raise HTTPException(502, "tenor upstream error")
    raw = resp.json().get("results", [])
    out = []
    for r in raw:
        tg = (r.get("media_formats") or {}).get("tinygif") or {}
        if tg.get("url"):
            out.append({
                "id": r.get("id"),
                "url": tg["url"],
                "width": (tg.get("dims") or [0, 0])[0],
                "height": (tg.get("dims") or [0, 0])[1],
            })
    return {"results": out}
```

- [ ] **Step 3: Verify**

- [ ] **Step 4: Commit**

```bash
git add app/media/routes.py tests/realtime/test_gif_search.py
git commit -m "feat(media): GET /media/gif/search via Tenor"
```

---

### Task 5.4: Structured JSON logging + remove print statements

**Files:**
- Create: `flame_backend/app/core/logging_config.py`
- Modify: `flame_backend/app/main.py`
- Modify: `flame_backend/app/core/redis.py` (remove any remaining `print`)

- [ ] **Step 1: Implement `logging_config.py`**

```python
"""Structured JSON logging. Call configure_logging() once at app startup."""
import logging
from pythonjsonlogger import jsonlogger


def configure_logging(level: str = "INFO") -> None:
    logger = logging.getLogger()
    for h in logger.handlers[:]:
        logger.removeHandler(h)
    handler = logging.StreamHandler()
    handler.setFormatter(jsonlogger.JsonFormatter(
        "%(asctime)s %(levelname)s %(name)s %(message)s",
        rename_fields={"levelname": "level", "asctime": "ts"},
    ))
    logger.addHandler(handler)
    logger.setLevel(getattr(logging, level.upper(), logging.INFO))
    # Quiet noisy third-party
    for noisy in ("pymongo", "passlib", "engineio", "socketio", "uvicorn.access"):
        logging.getLogger(noisy).setLevel(logging.WARNING)
```

In `app/main.py` lifespan startup, before any other code:
```python
from app.core.logging_config import configure_logging
configure_logging("DEBUG" if settings.DEBUG else "INFO")
```

Remove the existing `logging.basicConfig(...)` line and the existing third-party logger silencing block (now centralised).

- [ ] **Step 2: Remove `print(` from `app/core/`**

```bash
grep -rn 'print(' app/core/
# Replace each with logger.info(...) or logger.warning(...) as appropriate.
```

- [ ] **Step 3: Verify**

```bash
grep -rn 'print(' app/core/
```
Expected: empty output.

- [ ] **Step 4: Commit**

```bash
git add app/core/logging_config.py app/core/redis.py app/main.py
git commit -m "chore(observability): structured JSON logging, remove prints"
```

---

### Task 5.5: Prometheus metrics + `/metrics` endpoint

**Files:**
- Create: `flame_backend/app/core/metrics.py`
- Modify: `flame_backend/app/main.py`
- Modify: `flame_backend/app/realtime/handlers.py` (record metrics)

- [ ] **Step 1: Implement `metrics.py`**

```python
"""Prometheus metrics for the realtime layer."""
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

chat_messages_sent_total = Counter(
    "chat_messages_sent_total", "Messages sent by type", ["type"]
)
chat_acks_latency_seconds = Histogram(
    "chat_acks_latency_seconds", "Latency from message:send to ack",
    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0)
)
chat_idempotency_hits_total = Counter(
    "chat_idempotency_hits_total", "Idempotent replays caught"
)
socket_connections_active = Gauge(
    "socket_connections_active", "Active sockets"
)
socket_disconnects_total = Counter(
    "socket_disconnects_total", "Disconnects by reason", ["reason"]
)


def metrics_response():
    from fastapi import Response
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
```

In `app/main.py`:
```python
from app.core.metrics import metrics_response

@app.get("/metrics")
async def metrics():
    return metrics_response()
```

- [ ] **Step 2: Wire counters in `handlers.py`**

In `connect`:
```python
from app.core import metrics
metrics.socket_connections_active.inc()
```
In `disconnect`:
```python
metrics.socket_connections_active.dec()
metrics.socket_disconnects_total.labels(reason="normal").inc()
```
In `on_message_send`, around the persist+ack:
```python
import time as _t
start = _t.monotonic()
# ... existing logic ...
metrics.chat_acks_latency_seconds.observe(_t.monotonic() - start)
metrics.chat_messages_sent_total.labels(type=mtype).inc()
```
After the idempotency hit branch:
```python
if cached:
    metrics.chat_idempotency_hits_total.inc()
    return {"ok": True, "message": cached}
```

- [ ] **Step 3: Verify**

```bash
curl -s http://localhost:8000/metrics | head -20
```
Expected: lines starting with `# HELP chat_messages_sent_total`.

- [ ] **Step 4: Commit**

```bash
git add app/core/metrics.py app/main.py app/realtime/handlers.py
git commit -m "feat(observability): prometheus metrics + /metrics endpoint"
```

---

### Task 5.6: `GET /v1/config` runtime config endpoint

**Files:**
- Create: `flame_backend/app/core/config_routes.py`
- Modify: `flame_backend/app/main.py`

- [ ] **Step 1: Implement**

```python
# app/core/config_routes.py
from fastapi import APIRouter
from app.core.config import settings

router = APIRouter(tags=["config"])


@router.get("/config")
async def runtime_config():
    return {
        "chat_v2_enabled": bool(getattr(settings, "CHAT_V2_ENABLED", False)),
    }
```

In `app/main.py`:
```python
from app.core.config_routes import router as config_router
app.include_router(config_router, prefix=settings.API_V1_PREFIX)
```

- [ ] **Step 2: Verify**

```bash
curl -s http://localhost:8000/v1/config
```
Expected: `{"chat_v2_enabled": true}` or `false` depending on env.

- [ ] **Step 3: Commit**

```bash
git add app/core/config_routes.py app/main.py
git commit -m "feat(rollout): GET /v1/config for runtime feature flag"
```

---

# Section 6 — Flutter realtime layer

### Task 6.1: `lib/realtime/` skeleton + constants

**Files:**
- Create: `flame/lib/realtime/constants.dart`
- Create: `flame/lib/realtime/socket_state.dart`
- Create: `flame/lib/realtime/outbox_entry.dart`

- [ ] **Step 1: Implement `constants.dart`** (mirrors backend `app/realtime/constants.py`)

```dart
// lib/realtime/constants.dart
class RtEvents {
  static const connectionReady = 'connection:ready';
  static const forceDisconnect = 'force_disconnect';
  static const authTokenExpiring = 'auth:token_expiring';
  static const authTokenExpired = 'auth:token_expired';
  static const authTokenRefreshed = 'auth:token_refreshed';
  static const messageNew = 'message:new';
  static const messageSent = 'message:sent';
  static const messageEdited = 'message:edited';
  static const messageDeleted = 'message:deleted';
  static const messageSend = 'message:send';
  static const messageRead = 'message:read';
  static const reactionUpdate = 'reaction:update';
  static const pinUpdate = 'pin:update';
  static const matchNew = 'match:new';
  static const typingStart = 'typing:start';
  static const typingStop = 'typing:stop';
  static const typingUpdate = 'typing:update';
  static const readUpdate = 'read:update';
  static const presenceSubscribe = 'presence:subscribe';
  static const presenceUpdate = 'presence:update';
}

class RtTimeouts {
  static const ackTimeout = Duration(seconds: 8);
  static const typingCoalesce = Duration(seconds: 2);
  static const typingIdle = Duration(seconds: 3);
  static const offlineBannerAfter = Duration(seconds: 30);
}
```

- [ ] **Step 2: `socket_state.dart`**

```dart
enum SocketStatus { disconnected, connecting, connected, reconnecting, failed }

class SocketState {
  final SocketStatus status;
  final String? userId;
  final String? sid;
  final DateTime? sinceLastChange;
  const SocketState({required this.status, this.userId, this.sid, this.sinceLastChange});

  SocketState copy({SocketStatus? status, String? userId, String? sid, DateTime? sinceLastChange}) =>
      SocketState(
        status: status ?? this.status,
        userId: userId ?? this.userId,
        sid: sid ?? this.sid,
        sinceLastChange: sinceLastChange ?? this.sinceLastChange,
      );
}
```

- [ ] **Step 3: `outbox_entry.dart`**

```dart
import 'dart:convert';

enum OutboxStatus { pending, sending, sent, failed }

class OutboxEntry {
  final String clientMessageId;
  final String conversationId;
  final String type;
  final String content;
  final Map<String, dynamic>? media;
  final String? replyToMessageId;
  final OutboxStatus status;
  final int attempts;
  final String? errorCode;
  final DateTime createdAt;
  final String? canonicalMessageId;

  const OutboxEntry({
    required this.clientMessageId,
    required this.conversationId,
    required this.type,
    required this.content,
    this.media,
    this.replyToMessageId,
    this.status = OutboxStatus.pending,
    this.attempts = 0,
    this.errorCode,
    required this.createdAt,
    this.canonicalMessageId,
  });

  OutboxEntry copy({OutboxStatus? status, int? attempts, String? errorCode, String? canonicalMessageId}) =>
      OutboxEntry(
        clientMessageId: clientMessageId,
        conversationId: conversationId,
        type: type,
        content: content,
        media: media,
        replyToMessageId: replyToMessageId,
        status: status ?? this.status,
        attempts: attempts ?? this.attempts,
        errorCode: errorCode ?? this.errorCode,
        createdAt: createdAt,
        canonicalMessageId: canonicalMessageId ?? this.canonicalMessageId,
      );

  Map<String, dynamic> toJson() => {
    'cmid': clientMessageId,
    'cid': conversationId,
    'type': type,
    'content': content,
    'media': media,
    'replyTo': replyToMessageId,
    'status': status.name,
    'attempts': attempts,
    'errorCode': errorCode,
    'createdAt': createdAt.toIso8601String(),
    'canonical': canonicalMessageId,
  };

  static OutboxEntry fromJson(Map<String, dynamic> j) => OutboxEntry(
    clientMessageId: j['cmid'],
    conversationId: j['cid'],
    type: j['type'],
    content: j['content'],
    media: (j['media'] as Map?)?.cast<String, dynamic>(),
    replyToMessageId: j['replyTo'],
    status: OutboxStatus.values.byName(j['status']),
    attempts: j['attempts'] ?? 0,
    errorCode: j['errorCode'],
    createdAt: DateTime.parse(j['createdAt']),
    canonicalMessageId: j['canonical'],
  );

  String encode() => jsonEncode(toJson());
  static OutboxEntry decode(String s) => fromJson(jsonDecode(s));
}
```

- [ ] **Step 4: Verify analyze**

```bash
flutter analyze lib/realtime/
```

- [ ] **Step 5: Commit**

```bash
git add lib/realtime/constants.dart lib/realtime/socket_state.dart lib/realtime/outbox_entry.dart
git commit -m "feat(client): realtime constants, socket state, outbox entry"
```

---

### Task 6.2: `socket_client.dart` and `emitWithAckTimeout` wrapper (TDD)

**Files:**
- Create: `flame/lib/realtime/socket_client.dart`
- Create: `flame/test/realtime/socket_client_test.dart`

- [ ] **Step 1: Failing test**

```dart
// test/realtime/socket_client_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/realtime/socket_client.dart';
import 'package:flame/realtime/socket_state.dart';

void main() {
  group('SocketClient state', () {
    test('starts disconnected', () {
      final client = SocketClient();
      expect(client.state.status, SocketStatus.disconnected);
    });

    test('emitWithAckTimeout times out when no ack', () async {
      final client = SocketClient();
      // Inject a fake socket that never invokes ack
      client.injectFakeSocket(FakeNeverAckSocket());
      expect(
        () => client.emitWithAckTimeout('foo', {}, timeout: const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}

class FakeNeverAckSocket implements FakeSocket {
  @override
  void emitWithAck(String event, dynamic data, {Function? ack, bool binary = false}) {}
}
```

- [ ] **Step 2: Implement** (split into a thin testable interface + a real-socket adapter)

```dart
// lib/realtime/socket_client.dart
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/env.dart';
import 'socket_state.dart';

abstract class FakeSocket {
  void emitWithAck(String event, dynamic data, {Function? ack, bool binary = false});
}

class SocketClient {
  io.Socket? _socket;
  FakeSocket? _fakeSocket;
  SocketState _state = const SocketState(status: SocketStatus.disconnected);
  final _stateCtl = StreamController<SocketState>.broadcast();
  final _eventCtl = StreamController<(String, dynamic)>.broadcast();

  SocketState get state => _state;
  Stream<SocketState> get stateStream => _stateCtl.stream;
  Stream<(String, dynamic)> get eventStream => _eventCtl.stream;

  void injectFakeSocket(FakeSocket fake) { _fakeSocket = fake; }

  void connect({required String token, required String deviceId}) {
    _setState(const SocketState(status: SocketStatus.connecting));
    final socket = io.io(
      EnvConfig.current.wsBase,
      io.OptionBuilder()
        .setTransports(['websocket'])
        .setPath('/ws/socket.io')
        .setAuth({'token': token, 'device_id': deviceId})
        .enableReconnection()
        .setReconnectionAttempts(double.maxFinite.toInt())
        .build(),
    );
    socket.onConnect((_) {
      _setState(_state.copy(status: SocketStatus.connected, sinceLastChange: DateTime.now()));
    });
    socket.onDisconnect((_) {
      _setState(_state.copy(status: SocketStatus.reconnecting));
    });
    socket.onConnectError((e) {
      _setState(_state.copy(status: SocketStatus.failed));
    });
    socket.onAny((event, data) => _eventCtl.add((event, data)));
    _socket = socket;
  }

  Future<void> disconnect() async {
    _socket?.dispose();
    _socket = null;
    _setState(const SocketState(status: SocketStatus.disconnected));
  }

  void emit(String event, dynamic data) => _socket?.emit(event, data);

  Future<dynamic> emitWithAckTimeout(String event, dynamic data,
      {Duration timeout = const Duration(seconds: 8)}) {
    final completer = Completer<dynamic>();
    final s = _fakeSocket ?? _socket;
    if (s == null) {
      return Future.error(StateError('no socket'));
    }
    if (s is io.Socket) {
      s.emitWithAck(event, data, ack: (resp) {
        if (!completer.isCompleted) completer.complete(resp);
      });
    } else {
      (s as FakeSocket).emitWithAck(event, data, ack: (resp) {
        if (!completer.isCompleted) completer.complete(resp);
      });
    }
    return completer.future.timeout(timeout, onTimeout: () => throw TimeoutException('ack'));
  }

  void _setState(SocketState s) {
    _state = s;
    _stateCtl.add(s);
  }

  void dispose() {
    _socket?.dispose();
    _stateCtl.close();
    _eventCtl.close();
  }
}
```

- [ ] **Step 3: Verify**

```bash
cd /Users/davis/Desktop/Personal/flame
flutter test test/realtime/socket_client_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/realtime/socket_client.dart test/realtime/socket_client_test.dart
git commit -m "feat(client): SocketClient + emitWithAckTimeout wrapper"
```

---

### Task 6.3: `OutboxNotifier` with persistence (TDD)

**Files:**
- Create: `flame/lib/realtime/outbox.dart`
- Create: `flame/test/realtime/outbox_test.dart`

- [ ] **Step 1: Failing test**

```dart
// test/realtime/outbox_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/realtime/outbox.dart';
import 'package:flame/realtime/outbox_entry.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('enqueue persists across reconstruction', () async {
    final box = OutboxRepo();
    await box.load();
    await box.enqueue(_entry('cmid-1', 'c1'));
    expect((box.all).length, 1);

    final box2 = OutboxRepo();
    await box2.load();
    expect(box2.all.length, 1);
    expect(box2.all.first.clientMessageId, 'cmid-1');
  });

  test('markSent removes entry', () async {
    final box = OutboxRepo();
    await box.load();
    await box.enqueue(_entry('cmid-1', 'c1'));
    await box.markSent('cmid-1', canonicalMessageId: 'srv-1');
    expect(box.all, isEmpty);
  });

  test('markFailed after max attempts', () async {
    final box = OutboxRepo();
    await box.load();
    await box.enqueue(_entry('cmid-1', 'c1'));
    for (var i = 0; i < 5; i++) {
      await box.bumpAttempt('cmid-1');
    }
    expect(box.all.first.status, OutboxStatus.failed);
  });
}

OutboxEntry _entry(String cmid, String cid) => OutboxEntry(
  clientMessageId: cmid, conversationId: cid, type: 'text',
  content: 'x', createdAt: DateTime(2026, 1, 1));
```

- [ ] **Step 2: Implement**

```dart
// lib/realtime/outbox.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'outbox_entry.dart';

const _kKey = 'realtime_outbox_v1';
const int kMaxAttempts = 5;

class OutboxRepo {
  final List<OutboxEntry> _entries = [];
  late SharedPreferences _prefs;

  List<OutboxEntry> get all => List.unmodifiable(_entries);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString(_kKey);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    _entries
      ..clear()
      ..addAll(list.map(OutboxEntry.fromJson));
  }

  Future<void> _persist() async {
    await _prefs.setString(_kKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }

  Future<void> enqueue(OutboxEntry entry) async {
    _entries.add(entry);
    await _persist();
  }

  Future<void> markSending(String cmid) async {
    final i = _entries.indexWhere((e) => e.clientMessageId == cmid);
    if (i == -1) return;
    _entries[i] = _entries[i].copy(status: OutboxStatus.sending);
    await _persist();
  }

  Future<void> markSent(String cmid, {required String canonicalMessageId}) async {
    _entries.removeWhere((e) => e.clientMessageId == cmid);
    await _persist();
  }

  Future<void> bumpAttempt(String cmid, {String? errorCode}) async {
    final i = _entries.indexWhere((e) => e.clientMessageId == cmid);
    if (i == -1) return;
    final attempts = _entries[i].attempts + 1;
    final status = attempts >= kMaxAttempts ? OutboxStatus.failed : OutboxStatus.pending;
    _entries[i] = _entries[i].copy(status: status, attempts: attempts, errorCode: errorCode);
    await _persist();
  }

  Future<void> markFailedTerminal(String cmid, {required String errorCode}) async {
    final i = _entries.indexWhere((e) => e.clientMessageId == cmid);
    if (i == -1) return;
    _entries[i] = _entries[i].copy(status: OutboxStatus.failed, errorCode: errorCode);
    await _persist();
  }

  Future<void> resetSendingToPending() async {
    var changed = false;
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].status == OutboxStatus.sending) {
        _entries[i] = _entries[i].copy(status: OutboxStatus.pending);
        changed = true;
      }
    }
    if (changed) await _persist();
  }
}
```

- [ ] **Step 3: Verify**

```bash
flutter test test/realtime/outbox_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/realtime/outbox.dart test/realtime/outbox_test.dart
git commit -m "feat(client): persistent OutboxRepo with attempt tracking"
```

---

### Task 6.4: Riverpod providers — socket, outbox, messages, typing, presence

**Files:**
- Create: `flame/lib/realtime/providers.dart`
- Create: `flame/test/realtime/messages_provider_test.dart`

- [ ] **Step 1: Implement providers**

```dart
// lib/realtime/providers.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'constants.dart';
import 'outbox.dart';
import 'outbox_entry.dart';
import 'socket_client.dart';
import 'socket_state.dart';

final socketClientProvider = Provider<SocketClient>((ref) {
  final c = SocketClient();
  ref.onDispose(c.dispose);
  return c;
});

final socketStateProvider = StreamProvider<SocketState>((ref) {
  return ref.watch(socketClientProvider).stateStream;
});

final outboxRepoProvider = Provider<OutboxRepo>((ref) {
  final r = OutboxRepo();
  // Load on first access; consumers should `await` repo.load() before reading.
  return r;
});

final outboxProvider = StateNotifierProvider<OutboxNotifier, List<OutboxEntry>>((ref) {
  return OutboxNotifier(ref);
});

class OutboxNotifier extends StateNotifier<List<OutboxEntry>> {
  final Ref ref;
  OutboxNotifier(this.ref) : super([]) {
    _init();
  }

  Future<void> _init() async {
    final repo = ref.read(outboxRepoProvider);
    await repo.load();
    await repo.resetSendingToPending();
    state = repo.all;
  }

  Future<void> sendText({required String conversationId, required String content,
                         String? replyToMessageId}) async {
    final repo = ref.read(outboxRepoProvider);
    final entry = OutboxEntry(
      clientMessageId: const Uuid().v4(),
      conversationId: conversationId,
      type: 'text',
      content: content,
      replyToMessageId: replyToMessageId,
      createdAt: DateTime.now(),
    );
    await repo.enqueue(entry);
    state = repo.all;
    await _flushOne(entry);
  }

  Future<void> retry(String cmid) async {
    final repo = ref.read(outboxRepoProvider);
    final e = repo.all.firstWhere((x) => x.clientMessageId == cmid);
    state = repo.all;
    await _flushOne(e);
  }

  Future<void> flushAll() async {
    final repo = ref.read(outboxRepoProvider);
    for (final e in repo.all.where((e) => e.status != OutboxStatus.failed)) {
      await _flushOne(e);
    }
  }

  Future<void> _flushOne(OutboxEntry e) async {
    final repo = ref.read(outboxRepoProvider);
    final socket = ref.read(socketClientProvider);
    if (socket.state.status != SocketStatus.connected) return;
    await repo.markSending(e.clientMessageId);
    state = repo.all;
    try {
      final resp = await socket.emitWithAckTimeout(
        RtEvents.messageSend,
        {
          'client_message_id': e.clientMessageId,
          'conversation_id': e.conversationId,
          'type': e.type,
          'content': e.content,
          if (e.media != null) 'media': e.media,
          if (e.replyToMessageId != null) 'reply_to_message_id': e.replyToMessageId,
        },
        timeout: RtTimeouts.ackTimeout,
      );
      if (resp is Map && resp['ok'] == true) {
        await repo.markSent(e.clientMessageId,
                            canonicalMessageId: resp['message']['id']);
      } else if (resp is Map) {
        final code = (resp['error'] ?? const {})['code'] ?? 'UNKNOWN';
        if (code == 'TRANSIENT') {
          await repo.bumpAttempt(e.clientMessageId, errorCode: code);
        } else {
          await repo.markFailedTerminal(e.clientMessageId, errorCode: code);
        }
      } else {
        await repo.bumpAttempt(e.clientMessageId, errorCode: 'BAD_ACK');
      }
    } on TimeoutException {
      await repo.bumpAttempt(e.clientMessageId, errorCode: 'TIMEOUT');
    } catch (err) {
      await repo.bumpAttempt(e.clientMessageId, errorCode: 'NET');
    }
    state = repo.all;
  }
}
```

- [ ] **Step 2: Smoke test**

A real outbox/socket test against a running backend is integration-level; for unit confidence, the existing `outbox_test.dart` already covers the persistence + attempt logic. Skip a brittle provider-level mock.

- [ ] **Step 3: Verify analyze**

```bash
flutter analyze lib/realtime/
```

- [ ] **Step 4: Commit**

```bash
git add lib/realtime/providers.dart
git commit -m "feat(client): Riverpod providers for socket + outbox"
```

---

### Task 6.5: `api_client.dart` auto-refresh on 401 with mutex (TDD)

**Files:**
- Modify: `flame/lib/services/api_client.dart`
- Create: `flame/test/services/api_client_refresh_test.dart`

- [ ] **Step 1: Failing test**

```dart
// test/services/api_client_refresh_test.dart
// (Use a custom http.Client that the ApiClient is parameterised on.)
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flame/services/api_client.dart';

class _FakeClient extends http.BaseClient {
  final List<http.BaseRequest> calls = [];
  final List<http.Response> queue;
  _FakeClient(this.queue);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) async {
    calls.add(req);
    final resp = queue.removeAt(0);
    return http.StreamedResponse(
      Stream.value(utf8.encode(resp.body)),
      resp.statusCode,
      headers: resp.headers,
    );
  }
}

void main() {
  test('401 triggers refresh once for concurrent calls', () async {
    final fake = _FakeClient([
      http.Response('{}', 401),
      http.Response('{}', 401),
      http.Response('{"access_token":"new","refresh_token":"r"}', 200),
      http.Response('{"ok":true}', 200),
      http.Response('{"ok":true}', 200),
    ]);
    final client = ApiClient.testInstance(httpClient: fake);
    // (testInstance constructor is added below)
    final f1 = client.get('/x');
    final f2 = client.get('/y');
    final r1 = await f1;
    final r2 = await f2;
    expect(r1, isNotNull);
    expect(r2, isNotNull);
    final refreshCalls = fake.calls.where((c) => c.url.path.endsWith('/auth/refresh')).length;
    expect(refreshCalls, 1);
  });
}
```

- [ ] **Step 2: Implement wrapper + mutex**

In `api_client.dart`:
- Add a `Completer<void>?  _refreshing;` field.
- Replace each direct `http.get/post/...` call with `await _authenticated((c) => c.get(...))`.
- Implement:

```dart
Future<http.Response> _authenticated(Future<http.Response> Function(http.Client) op) async {
  var resp = await op(_httpClient);
  if (resp.statusCode == 401 && !_isRefreshUrl(resp)) {
    if (_refreshing == null) {
      _refreshing = Completer<void>();
      try {
        final ok = await _doRefresh();
        if (!ok) {
          _refreshing!.completeError('refresh_failed');
          await _onAuthLost?.call();
          throw _AuthLost();
        }
        _refreshing!.complete();
      } catch (e) {
        if (!_refreshing!.isCompleted) _refreshing!.completeError(e);
        rethrow;
      } finally {
        _refreshing = null;
      }
    } else {
      await _refreshing!.future;
    }
    resp = await op(_httpClient);
  }
  return resp;
}
```

Inject `_httpClient` via constructor; `ApiClient.testInstance(httpClient: ...)` for tests.

- [ ] **Step 3: Verify**

```bash
flutter test test/services/api_client_refresh_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/services/api_client.dart test/services/api_client_refresh_test.dart
git commit -m "feat(client): ApiClient auto-refreshes on 401 with mutex"
```

---

# Section 7 — Flutter UI integration

### Task 7.1: Refactor `chat_screen.dart` to remove `setState`

**Files:**
- Modify: `flame/lib/screens/chat/chat_screen.dart`
- Modify: `flame/lib/providers/chat_provider.dart` (replace with new providers from Task 6.4)

- [ ] **Step 1: Inventory current `setState` calls**

```bash
cd /Users/davis/Desktop/Personal/flame
grep -n "setState" lib/screens/chat/chat_screen.dart
```
Expected: at least 4 hits (per audit). Each must be replaced with a provider read/write.

- [ ] **Step 2: Refactor — replace each `setState` block**

Pattern:
- Local `List<Message>` → `ref.watch(messagesProvider(conversationId))`.
- Local `bool _isTyping` for the peer → `ref.watch(typingProvider(conversationId))`.
- Local pending-send list → `ref.watch(outboxProvider).where((e) => e.conversationId == cid)`.
- Local typing-debounce → keep `Timer` + `TextEditingController` listener; emit `typing:start` / `typing:stop` via `socketClientProvider`.

Strip the `StatefulWidget` state class of all `_messages = [...]` style fields. Keep only `TextEditingController` and `ScrollController`.

- [ ] **Step 3: Wire send action**

Replace `_sendMessage` body with:
```dart
ref.read(outboxProvider.notifier).sendText(
  conversationId: widget.conversationId,
  content: textController.text.trim(),
  replyToMessageId: replyTo?.id,
);
textController.clear();
```

- [ ] **Step 4: Run + smoke**

```bash
flutter analyze lib/screens/chat/
flutter run --dart-define=APP_ENV=local
# Open a conversation, type, send; verify the message appears with pending indicator
# and transitions to sent within ~50ms when backend is up.
```

- [ ] **Step 5: Commit**

```bash
git add lib/screens/chat/chat_screen.dart lib/providers/chat_provider.dart
git commit -m "refactor(chat_screen): remove setState; route through Riverpod"
```

---

### Task 7.2: Connection banner + per-message status indicators

**Files:**
- Create: `flame/lib/realtime/widgets/connection_banner.dart`
- Modify: `flame/lib/screens/chat/chat_screen.dart` (mount the banner)
- Modify: any message-row widget to show per-status icons

- [ ] **Step 1: Implement `connection_banner.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../socket_state.dart';
import '../providers.dart';
import '../constants.dart';

class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(socketStateProvider).valueOrNull;
    if (state == null || state.status == SocketStatus.connected) {
      return const SizedBox.shrink();
    }
    final stuckOffline = state.sinceLastChange != null &&
        DateTime.now().difference(state.sinceLastChange!) > RtTimeouts.offlineBannerAfter;
    final isOffline = stuckOffline || state.status == SocketStatus.failed;
    return Container(
      width: double.infinity,
      color: isOffline ? Colors.red.shade400 : Colors.amber.shade400,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(child: Text(
        isOffline ? 'Offline' : 'Reconnecting…',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      )),
    );
  }
}
```

- [ ] **Step 2: Mount in chat scaffold above the message list**

In `chat_screen.dart`, in the AppBar's `bottom` slot or just below it:
```dart
const ConnectionBanner(),
```

- [ ] **Step 3: Per-message status icons**

In the message-row widget, show a trailing icon based on `OutboxStatus`:
- `pending` → `Icons.access_time` grey
- `sending` → small `CircularProgressIndicator(strokeWidth: 1.5)`
- `sent` → single tick (`Icons.check`)
- `read` → double tick (use overlap of two `Icons.check`)
- `failed` → `Icons.error` red, tappable to call `ref.read(outboxProvider.notifier).retry(...)`.

- [ ] **Step 4: Verify analyze + visual**

```bash
flutter analyze lib/realtime/widgets/ lib/screens/chat/
```

- [ ] **Step 5: Commit**

```bash
git add lib/realtime/widgets/ lib/screens/chat/
git commit -m "feat(chat): connection banner + per-message status icons"
```

---

### Task 7.3: Sticker picker + GIF picker integration

**Files:**
- Create: `flame/lib/realtime/widgets/sticker_picker.dart`
- Create: `flame/lib/realtime/widgets/gif_picker.dart`
- Modify: `flame/lib/screens/chat/chat_screen.dart` (mount picker bar)

- [ ] **Step 1: `sticker_picker.dart`**

Pull stickers from existing `chat_service.dart` sticker endpoints. Render a grid; on tap, call:
```dart
ref.read(outboxProvider.notifier).sendSticker(
  conversationId: cid, stickerId: sticker.id);
```
Add `sendSticker` and `sendGif` methods to `OutboxNotifier` analogous to `sendText`.

- [ ] **Step 2: `gif_picker.dart`**

Search field debounced 300ms. On query, hit `GET /v1/media/gif/search?q=...` via `ApiClient`. Render results in a 2-column grid. On tap, call `sendGif(conversationId, mediaUrl, width, height)`.

- [ ] **Step 3: Mount toggle button in chat input bar**

Replace the existing "GIF coming soon" placeholder (`chat_screen.dart` audit ref: lines 214–216) with a real picker toggle.

- [ ] **Step 4: Verify + commit**

```bash
flutter analyze lib/realtime/widgets/
git add lib/realtime/widgets/ lib/screens/chat/ lib/realtime/providers.dart
git commit -m "feat(chat): sticker + GIF pickers integrated"
```

---

### Task 7.4: Runtime config gate (chat_v2 fallback)

**Files:**
- Create: `flame/lib/services/runtime_config_service.dart`
- Modify: `flame/lib/main.dart` (or wherever app bootstraps) to await config before mounting chat screens
- Keep: `flame/lib/services/websocket_service.dart` and the legacy chat path as a fallback

- [ ] **Step 1: Implement `runtime_config_service.dart`**

```dart
import 'dart:convert';
import '../services/api_client.dart';

class RuntimeConfig {
  final bool chatV2Enabled;
  RuntimeConfig({required this.chatV2Enabled});
}

class RuntimeConfigService {
  final ApiClient api;
  RuntimeConfigService(this.api);
  RuntimeConfig _cached = RuntimeConfig(chatV2Enabled: false);
  RuntimeConfig get current => _cached;

  Future<RuntimeConfig> fetch() async {
    final resp = await api.get('/config');
    final body = jsonDecode(resp.body);
    _cached = RuntimeConfig(chatV2Enabled: (body['chat_v2_enabled'] ?? false) == true);
    return _cached;
  }
}
```

- [ ] **Step 2: Provider + bootstrap**

```dart
final runtimeConfigProvider = Provider<RuntimeConfigService>((ref) =>
    RuntimeConfigService(ref.read(apiClientProvider)));
final chatV2EnabledProvider = FutureProvider<bool>((ref) async =>
    (await ref.read(runtimeConfigProvider).fetch()).chatV2Enabled);
```

In the chat-screen route, branch:
```dart
final flag = ref.watch(chatV2EnabledProvider);
return flag.when(
  data: (enabled) => enabled
      ? const NewChatScreen(...)  // Uses Section 6 providers
      : const LegacyChatScreen(...),  // Existing screen
  loading: () => const Center(child: CircularProgressIndicator()),
  error: (_, __) => const LegacyChatScreen(...),
);
```

- [ ] **Step 3: Commit**

```bash
git add lib/services/runtime_config_service.dart lib/main.dart lib/screens/
git commit -m "feat(rollout): runtime chat_v2 gate with legacy fallback"
```

---

# Section 8 — Verification

### Task 8.1: Backend test suite to green; idempotency load test

**Files:**
- Create: `flame_backend/tests/realtime/test_idempotency_load.py`

- [ ] **Step 1: Implement load test**

```python
import pytest, asyncio, uuid


@pytest.mark.asyncio
async def test_idempotency_under_concurrency(make_socket_client, conversation_pair):
    from app.core.security import create_access_token
    u1, _, conv = conversation_pair
    t = create_access_token({"sub": str(u1.id)})
    c = await make_socket_client(t)
    await c.receive(timeout=2)
    cmid = str(uuid.uuid4())
    payload = {"client_message_id": cmid, "conversation_id": str(conv.id),
               "type": "text", "content": "boom"}

    async def send_one():
        return await c.call("message:send", payload, timeout=5)

    results = await asyncio.gather(*[send_one() for _ in range(100)])
    canonical_ids = {r["message"]["id"] for r in results if r["ok"]}
    assert len(canonical_ids) == 1
    from app.models.message import Message
    count = await Message.find({"client_message_id": cmid}).count()
    assert count == 1
```

- [ ] **Step 2: Full suite**

```bash
cd /Users/davis/Desktop/Personal/flame_backend
source venv/bin/activate
pytest tests/realtime/ -v --tb=short
```
Expected: all tests pass; suite runtime <30s on local hardware.

- [ ] **Step 3: Coverage check**

```bash
pip install coverage
coverage run -m pytest tests/realtime/
coverage report --include='app/realtime/*'
```
Expected: ≥80% lines on `app/realtime/`.

- [ ] **Step 4: Commit**

```bash
git add tests/realtime/test_idempotency_load.py
git commit -m "test: idempotency load test (100x replay → 1 row)"
```

---

### Task 8.2: Flutter test suite to green

- [ ] **Step 1: Run all tests**

```bash
cd /Users/davis/Desktop/Personal/flame
flutter test
```
Expected: green. If any flake, fix root cause (no `--retry`).

- [ ] **Step 2: Commit any fixes** (no-op if green)

---

### Task 8.3: Manual QA matrix execution + flag flip

**Files:**
- Create: `flame_backend/docs/qa-matrix-phase-1.md`

- [ ] **Step 1: Write the matrix doc**

```markdown
# Phase 1 QA Matrix

Run each row against a local backend (`CHAT_V2_ENABLED=true uvicorn app.main:asgi_app`)
and a Flutter build (`flutter run --dart-define=APP_ENV=local`).

## A. Airplane mode flush
**Steps:** enable airplane mode, send 3 messages, disable airplane mode.
**Pass:** all 3 transition pending → sending → sent within 8s of reconnect.
**Verify in Mongo:** `db.messages.countDocuments({client_message_id: {$in: [...]}})` returns 3.

## B. Force-quit replay
**Steps:** start a send, force-quit during the 8s ack window, reopen.
**Pass:** message either `sent` or `pending` (not failed); on Mongo, exactly 1 row.

## C. Two-device sync
**Steps:** log in on phone + simulator; send from phone.
**Pass:** simulator sees the message within 1s; both devices identical.

## D. Long-lock send
**Steps:** type, lock for 90s, unlock, send.
**Pass:** acks within 3s of unlock; logs show one disconnect+reconnect, no storm.

## E. Idempotency load test
**Run:** `pytest tests/realtime/test_idempotency_load.py -v`. Pass = green.
```

- [ ] **Step 2: Execute each row, mark pass/fail in a checklist**

If any row fails, fix the underlying bug (open issue, write failing test first, fix, verify).

- [ ] **Step 3: Final verification commands**

```bash
cd /Users/davis/Desktop/Personal/flame_backend
grep -rn 'print(' app/core/   # must be empty
grep -rn 'CHAT_V2_ENABLED' app/  # must find the gate
pytest tests/realtime/ -v
```

```bash
cd /Users/davis/Desktop/Personal/flame
flutter analyze
flutter test
```

- [ ] **Step 4: Flip the flag in dev**

```bash
echo "CHAT_V2_ENABLED=true" >> /Users/davis/Desktop/Personal/flame_backend/.env
```
(Or set via env at uvicorn startup.)

- [ ] **Step 5: Run the Flutter app against dev backend**

```bash
flutter run --dart-define=APP_ENV=local
```
Smoke: open a conversation; send a message; verify it appears on the other device; force-quit; replay.

- [ ] **Step 6: Commit QA doc**

```bash
git add docs/qa-matrix-phase-1.md
git commit -m "docs: Phase 1 QA matrix with verifiable post-conditions"
```

---

# Done criteria checklist

Phase 1 is shippable when **every** box below is checked:

- [ ] All `git log --oneline` commits since this plan started reflect the section ordering above.
- [ ] `pytest tests/realtime/ -v` returns 0 in <30s.
- [ ] `coverage report --include='app/realtime/*'` shows ≥80%.
- [ ] `flutter test` returns 0.
- [ ] `flutter analyze` returns 0.
- [ ] `grep -rn 'print(' app/core/` returns nothing.
- [ ] `grep -rn 'CHAT_V2_ENABLED' app/` finds the conditional mount.
- [ ] All 5 QA matrix rows checked off.
- [ ] DO Spaces bucket policy + CORS verified via `curl -X OPTIONS`.
- [ ] `redis-cli CONFIG GET notify-keyspace-events` returns `Ex` on dev (and on staging/prod before flag flip).
- [ ] No ESM/Lint warnings in either repo's analyze output.

---

# Open items deferred to a follow-up

1. Production-grade keyspace-notifications fallback — if managed Redis prohibits it, swap the in-process `_grace_offline_broadcast` for a Redis sorted-set sentinel pattern (see spec Open Questions).
2. Tenor API key — switch from keyless to keyed if rate-limited.
3. Phase 2 will: drop legacy `user1_unread_count`/`user2_unread_count` columns, drop legacy `MessageStatus` field, add HEAD existence check on media URLs, delete deprecated upload endpoints, delete `lib/services/websocket_service.dart` after 7 days of CHAT_V2_ENABLED=true on prod.

---

**End of plan.**

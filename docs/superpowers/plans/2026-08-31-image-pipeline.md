# Image Pipeline Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve right-sized images and stop photo uploads from blocking the API's event loop.

**Architecture:** A new pure module generates three WebP variants per photo; storage moves every boto3 call off the event loop and uploads the variants concurrently; the `Photo` model gains two optional URL fields so the change is invisible to clients already in the field; a one-off script backfills existing photos. The Flutter app then learns to request the right variant and decode at draw size.

**Tech Stack:** Python 3.12, FastAPI, Beanie/Motor, Pillow, boto3 (DigitalOcean Spaces), pytest + pytest-asyncio. Flutter 3.x, Riverpod, `cached_network_image`.

**Spec:** `docs/superpowers/specs/2026-08-31-image-pipeline-design.md`

---

## Read this before Task 1

**Two repositories.** Tasks 1-10 are in `/Users/davis/Desktop/Personal/flame_backend`. Tasks 11-17 are in `/Users/davis/Desktop/Personal/flame` (the Flutter app). Every path below is relative to the repository named in the task's **Repo** line.

**Two deploys, in order.** Tasks 1-10 ship first and are invisible to the app version already in the store. Tasks 11-17 ship after. Do not interleave them.

**The rule that cannot be relaxed.** Backend `d480c8c` and app `1.0.0+10001` are live as of 2026-08-30. The backfill in Task 9 *adds* `url_medium` and `url_thumb` beside the original and must never rewrite `url` or delete the object it names. Rewriting it would 404 every photo on every installed client at once.

**The backend has no tests.** No `tests/` directory, no `conftest.py`, no pytest config. `pytest` and `pytest-asyncio` are in `requirements.txt` and unused, and the `.pytest_cache` in the repo is stale junk from an unrelated project — ignore it. Task 1 builds the harness. Every backend test in this plan is designed to need **no MongoDB and no Redis**; that is why validation and backfill logic get extracted into pure functions rather than tested through routes.

**The app has 143 tests and a strong test culture.** Follow the existing style — see `test/screens/chat/chat_header_test.dart` for the house pattern.

---

# DEPLOY 1 — BACKEND

## Task 1: Test harness

**Repo:** `flame_backend`

**Files:**
- Create: `pytest.ini`
- Create: `tests/__init__.py`
- Create: `tests/core/__init__.py`
- Create: `tests/core/test_harness.py`

- [ ] **Step 1: Write the smoke test**

`tests/core/test_harness.py`:

```python
import asyncio


def test_sync_test_runs():
    assert True


async def test_async_test_runs():
    await asyncio.sleep(0)
    assert True
```

- [ ] **Step 2: Run it and watch the async test fail**

```bash
cd /Users/davis/Desktop/Personal/flame_backend
./venv/bin/python -m pytest tests/ -v
```

Expected: `test_sync_test_runs` PASSES, `test_async_test_runs` is SKIPPED with a warning about async support. That skip is the failure we are fixing — an async test that silently skips is worse than one that fails.

- [ ] **Step 3: Add the config**

`pytest.ini`:

```ini
[pytest]
testpaths = tests
asyncio_mode = auto
filterwarnings =
    ignore::DeprecationWarning
```

`tests/__init__.py` and `tests/core/__init__.py` are both empty files.

- [ ] **Step 4: Run again**

```bash
./venv/bin/python -m pytest tests/ -v
```

Expected: both tests PASS. If `test_async_test_runs` still skips, `pytest-asyncio` is not installed — run `./venv/bin/pip install -r requirements.txt`.

- [ ] **Step 5: Commit**

```bash
git checkout -b image-pipeline
git add pytest.ini tests/
git commit -m "test: add pytest harness

The repo had pytest and pytest-asyncio in requirements and no tests, no
config and no tests directory. asyncio_mode=auto so async tests run
instead of silently skipping."
```

---

## Task 2: Variant generation

**Repo:** `flame_backend`

The pure core of this work: bytes in, three sized WebP images out. No S3, no FastAPI, no config, no network — which is what makes it testable with a synthetic image and no infrastructure.

**Files:**
- Create: `app/core/images.py`
- Create: `tests/core/test_images.py`

- [ ] **Step 1: Write the failing tests**

`tests/core/test_images.py`:

```python
import io

import pytest
from PIL import Image

from app.core.images import (
    VARIANT_EDGES,
    ImageProcessingError,
    generate_variants,
)


def _jpeg(size=(2000, 1000), colour="red", orientation=None) -> bytes:
    """A real JPEG. `orientation` writes the EXIF tag without rotating pixels,
    which is exactly what a phone camera does."""
    img = Image.new("RGB", size, colour)
    buf = io.BytesIO()
    if orientation is None:
        img.save(buf, format="JPEG")
    else:
        exif = img.getexif()
        exif[274] = orientation  # 274 == Orientation
        img.save(buf, format="JPEG", exif=exif)
    return buf.getvalue()


def _open(data: bytes) -> Image.Image:
    return Image.open(io.BytesIO(data))


def test_returns_one_variant_per_configured_edge():
    out = generate_variants(_jpeg())
    assert set(out) == set(VARIANT_EDGES)


def test_each_variant_is_webp():
    for data in generate_variants(_jpeg()).values():
        assert _open(data).format == "WEBP"


def test_long_edge_matches_the_ladder():
    out = generate_variants(_jpeg(size=(2000, 1000)))
    assert max(_open(out["full"]).size) == 1440
    assert max(_open(out["medium"]).size) == 512
    assert max(_open(out["thumb"]).size) == 256


def test_aspect_ratio_is_preserved():
    out = generate_variants(_jpeg(size=(2000, 1000)))
    w, h = _open(out["thumb"]).size
    assert w == 2 * h


def test_never_upscales_past_the_source():
    # A 300px source must not be blown up to 1440.
    out = generate_variants(_jpeg(size=(300, 300)))
    assert max(_open(out["full"]).size) == 300
    assert max(_open(out["thumb"]).size) == 256


def test_exif_orientation_is_applied_to_pixels():
    # Orientation 6 means "rotate 90 degrees to display". A 1000x2000 stored
    # image is therefore a 2000x1000 image once upright.
    out = generate_variants(_jpeg(size=(1000, 2000), orientation=6))
    w, h = _open(out["full"]).size
    assert w > h, "portrait-tagged photo came out sideways"


def test_exif_is_stripped_from_output():
    out = generate_variants(_jpeg(orientation=6))
    # A dating app must not serve the camera's GPS tags from a public CDN.
    assert not _open(out["full"]).getexif()


def test_rejects_bytes_that_are_not_an_image():
    with pytest.raises(ImageProcessingError):
        generate_variants(b"this is not an image")


def test_rejects_a_decompression_bomb():
    from app.core import images

    # A real bomb file would be slow to build; lowering the ceiling proves the
    # guard is wired to the same limit the module sets.
    original = images.MAX_PIXELS
    images.MAX_PIXELS = 100
    try:
        with pytest.raises(ImageProcessingError):
            generate_variants(_jpeg(size=(2000, 1000)))
    finally:
        images.MAX_PIXELS = original
```

- [ ] **Step 2: Run to verify they fail**

```bash
./venv/bin/python -m pytest tests/core/test_images.py -v
```

Expected: collection error, `ModuleNotFoundError: No module named 'app.core.images'`.

- [ ] **Step 3: Write the implementation**

`app/core/images.py`:

```python
"""Sized image variants.

Pure on purpose: no S3, no FastAPI, no settings, no network. Everything that
needs infrastructure lives in `storage.py`, so the part with the actual logic
(orientation, aspect, quality, upscale guard) can be tested against a synthetic
image with nothing running.
"""
from __future__ import annotations

import io
from typing import Dict

from PIL import Image, ImageOps

# Long edge in pixels, per surface. `full` is 1440 rather than the old 1024
# because a full-bleed deck card is ~390pt at 3x = ~1170 physical pixels, so
# 1024 was already being upscaled on the card.
VARIANT_EDGES: Dict[str, int] = {
    "full": 1440,
    "medium": 512,
    "thumb": 256,
}

WEBP_QUALITY = 82

# Pillow's own default (~178M pixels) is high enough that a crafted file can
# exhaust memory before any of our checks run.
MAX_PIXELS = 50_000_000


class ImageProcessingError(ValueError):
    """The bytes handed in are not a usable image."""


def generate_variants(data: bytes) -> Dict[str, bytes]:
    """Return `{variant_name: webp_bytes}` for every entry in VARIANT_EDGES.

    Raises ImageProcessingError if the bytes are unreadable or hostile.
    """
    Image.MAX_IMAGE_PIXELS = MAX_PIXELS
    try:
        with Image.open(io.BytesIO(data)) as opened:
            # Applies the camera's orientation tag to the pixels and drops the
            # tag, so a portrait photo is stored upright rather than
            # sideways-with-a-flag.
            upright = ImageOps.exif_transpose(opened)
            source = (
                upright.convert("RGBA")
                if upright.mode in ("RGBA", "LA", "P")
                else upright.convert("RGB")
            )

            source_edge = max(source.size)
            out: Dict[str, bytes] = {}
            for name, edge in VARIANT_EDGES.items():
                # min() is the upscale guard: a 300px source yields a 300px
                # "full", never a blurry 1440.
                target = min(edge, source_edge)
                variant = source.copy()
                variant.thumbnail((target, target), Image.LANCZOS)
                buf = io.BytesIO()
                # No exif= argument. Re-encoding drops every tag, GPS included.
                variant.save(buf, format="WEBP", quality=WEBP_QUALITY, method=4)
                out[name] = buf.getvalue()
            return out
    except Image.DecompressionBombError as exc:
        raise ImageProcessingError("Image is too large to process") from exc
    except (OSError, ValueError) as exc:
        raise ImageProcessingError("Could not read image") from exc
```

- [ ] **Step 4: Run to verify they pass**

```bash
./venv/bin/python -m pytest tests/core/test_images.py -v
```

Expected: 9 passed.

- [ ] **Step 5: Commit**

```bash
git add app/core/images.py tests/core/test_images.py
git commit -m "feat(images): generate sized WebP variants

Pure module: bytes in, three variants out. Applies EXIF orientation to
the pixels and drops the tag, which also stops the camera's GPS
coordinates being served from a public CDN."
```

---

## Task 3: Photo model gains variant fields

**Repo:** `flame_backend`

**Files:**
- Modify: `app/models/user.py:16-20`
- Create: `tests/models/__init__.py`
- Create: `tests/models/test_photo.py`

- [ ] **Step 1: Write the failing test**

`tests/models/test_photo.py`:

```python
from app.models.user import Photo


def test_old_documents_without_variants_still_load():
    # Every photo currently in the database looks like this. If this breaks,
    # the deploy takes production with it.
    photo = Photo(id="p1", url="https://cdn/a.jpg", is_primary=True, order=0)
    assert photo.url_medium is None
    assert photo.url_thumb is None


def test_variants_round_trip():
    photo = Photo(
        id="p1",
        url="https://cdn/a.jpg",
        url_medium="https://cdn/a_medium.webp",
        url_thumb="https://cdn/a_thumb.webp",
    )
    dumped = photo.model_dump()
    assert dumped["url_thumb"] == "https://cdn/a_thumb.webp"
    assert Photo(**dumped) == photo


def test_url_is_still_required():
    import pytest
    from pydantic import ValidationError

    with pytest.raises(ValidationError):
        Photo(id="p1")
```

- [ ] **Step 2: Run to verify it fails**

```bash
./venv/bin/python -m pytest tests/models/test_photo.py -v
```

Expected: FAIL — `Photo` has no attribute `url_medium`.

- [ ] **Step 3: Add the fields**

In `app/models/user.py`, replace the `Photo` class (currently lines 16-20):

```python
class Photo(BaseModel):
    id: str
    # The full-size image. Its value must stay stable for photos that already
    # exist: clients in the field read this field and nothing else, so
    # repointing it would 404 every photo at once. See Task 9.
    url: str
    url_medium: Optional[str] = None
    url_thumb: Optional[str] = None
    is_primary: bool = False
    order: int = 0
```

- [ ] **Step 4: Run to verify it passes**

```bash
./venv/bin/python -m pytest tests/models/ -v
```

Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add app/models/user.py tests/models/
git commit -m "feat(photos): add optional variant URLs to Photo

Optional with a None default so documents written before this deploy
load unchanged, and so the API can ship before the backfill finishes."
```

---

## Task 4: Enforce the upload limits that already exist in config

**Repo:** `flame_backend`

`MAX_PHOTO_SIZE` (`config.py:35`) and `MAX_PHOTOS_PER_USER` (`config.py:37`) are referenced nowhere. `validate_image_file` (`users/routes.py:25`) checks content type and returns. Extracting the rules into a pure function is what lets them be tested without a running app.

**Files:**
- Create: `app/core/uploads.py`
- Create: `tests/core/test_uploads.py`
- Modify: `app/users/routes.py` (remove local `validate_image_file`, import from the new module)

- [ ] **Step 1: Write the failing tests**

`tests/core/test_uploads.py`:

```python
import pytest

from app.core.exceptions import AppException
from app.core.uploads import (
    ALLOWED_IMAGE_TYPES,
    validate_image_upload,
    validate_photo_count,
)


def test_accepts_every_allowed_type():
    for content_type in ALLOWED_IMAGE_TYPES:
        validate_image_upload(content_type, size=1024, max_size=10 * 1024 * 1024)


def test_rejects_a_disallowed_type():
    with pytest.raises(AppException) as exc:
        validate_image_upload("application/pdf", size=1024, max_size=10 * 1024 * 1024)
    assert exc.value.code == "INVALID_FILE_TYPE"


def test_rejects_a_missing_type():
    with pytest.raises(AppException):
        validate_image_upload(None, size=1024, max_size=10 * 1024 * 1024)


def test_rejects_a_file_over_the_ceiling():
    with pytest.raises(AppException) as exc:
        validate_image_upload("image/jpeg", size=11 * 1024 * 1024, max_size=10 * 1024 * 1024)
    assert exc.value.code == "FILE_TOO_LARGE"


def test_accepts_a_file_exactly_at_the_ceiling():
    validate_image_upload("image/jpeg", size=10, max_size=10)


def test_rejects_one_photo_past_the_limit():
    with pytest.raises(AppException) as exc:
        validate_photo_count(current=6, maximum=6)
    assert exc.value.code == "TOO_MANY_PHOTOS"


def test_accepts_a_photo_that_fits():
    validate_photo_count(current=5, maximum=6)
```

- [ ] **Step 2: Run to verify they fail**

```bash
./venv/bin/python -m pytest tests/core/test_uploads.py -v
```

Expected: `ModuleNotFoundError: No module named 'app.core.uploads'`.

- [ ] **Step 3: Write the module**

`app/core/uploads.py`:

```python
"""Upload validation rules.

Pure functions taking primitives rather than an UploadFile, so the rules can be
tested without FastAPI, a request, or a database.
"""
from __future__ import annotations

from typing import Optional, Set

from app.core.exceptions import AppException

ALLOWED_IMAGE_TYPES: Set[str] = {
    "image/jpeg",
    "image/jpg",
    "image/png",
    "image/gif",
    "image/webp",
}


def validate_image_upload(content_type: Optional[str], size: int, *, max_size: int) -> None:
    """Raise AppException unless this is an image we accept, at a size we accept."""
    if content_type not in ALLOWED_IMAGE_TYPES:
        raise AppException(
            status_code=400,
            code="INVALID_FILE_TYPE",
            message="File type not allowed. Supported: JPEG, PNG, GIF, WebP",
        )
    if size > max_size:
        raise AppException(
            status_code=400,
            code="FILE_TOO_LARGE",
            message=f"Image must be {max_size // (1024 * 1024)}MB or smaller",
        )


def validate_photo_count(current: int, *, maximum: int) -> None:
    """Raise AppException if adding one more photo would exceed the limit."""
    if current >= maximum:
        raise AppException(
            status_code=400,
            code="TOO_MANY_PHOTOS",
            message=f"You can have at most {maximum} photos",
        )
```

**The signature is verified.** `AppException.__init__` (`app/core/exceptions.py:8`) takes `status_code`, `code`, `message` and an optional `details`, and assigns `self.code = code`, so the `exc.value.code` assertions in the tests above work as written. No adjustment needed.

- [ ] **Step 4: Run to verify they pass**

```bash
./venv/bin/python -m pytest tests/core/test_uploads.py -v
```

Expected: 7 passed.

- [ ] **Step 5: Point the route at it**

In `app/users/routes.py`, delete the local `validate_image_file` function (lines 25-32) and the local `ALLOWED_IMAGE_TYPES` constant, then import the new helpers:

```python
from app.core.uploads import validate_image_upload, validate_photo_count
```

Do not change the call sites yet — Task 7 rewrites those routes wholesale. For now, add a thin shim so the module still imports:

```python
def validate_image_file(file: UploadFile) -> None:
    """Deprecated shim; Task 7 replaces the call sites with the bytes-aware path."""
    validate_image_upload(file.content_type, size=0, max_size=settings.MAX_PHOTO_SIZE)
```

- [ ] **Step 6: Verify nothing broke on import**

```bash
./venv/bin/python -c "import app.main" && ./venv/bin/python -m pytest tests/ -v
```

Expected: no import error, all tests pass.

- [ ] **Step 7: Commit**

```bash
git add app/core/uploads.py tests/core/test_uploads.py app/users/routes.py
git commit -m "feat(uploads): enforce MAX_PHOTO_SIZE and MAX_PHOTOS_PER_USER

Both have been defined in config and referenced nowhere since they were
written. Rules extracted as pure functions so they are testable without
a request or a database."
```

---

## Task 5: Get boto3 off the event loop

**Repo:** `flame_backend`

The single most valuable change in this plan. `put_object` (`storage.py:58`, `:85`) and `delete_object` (`storage.py:103`) are synchronous calls inside `async def` on a one-worker uvicorn, so every upload freezes deck fetches, chat sends and WebSocket frames for the length of a round trip to Spaces.

**Files:**
- Modify: `app/core/storage.py`
- Create: `tests/core/test_storage.py`

- [ ] **Step 1: Write the failing tests**

`tests/core/test_storage.py`:

```python
import threading

from app.core.storage import CACHE_CONTROL, StorageService


class FakeS3Client:
    """Records what it was called with, and on which thread."""

    def __init__(self):
        self.puts = []
        self.deletes = []
        self.threads = []

    def put_object(self, **kwargs):
        self.threads.append(threading.current_thread().name)
        self.puts.append(kwargs)

    def delete_object(self, **kwargs):
        self.threads.append(threading.current_thread().name)
        self.deletes.append(kwargs)


def _service():
    fake = FakeS3Client()
    return StorageService(client=fake), fake


async def test_put_does_not_run_on_the_event_loop_thread():
    service, fake = _service()
    await service.upload_bytes(b"x", "a.webp", folder="photos", content_type="image/webp")
    # This is the whole point of the task: a blocking S3 call on the main
    # thread stalls every other request on the worker.
    assert "MainThread" not in fake.threads


async def test_delete_does_not_run_on_the_event_loop_thread():
    service, fake = _service()
    await service.delete_file(f"{service.cdn_url}/some/key.jpg")
    assert "MainThread" not in fake.threads


async def test_put_sets_immutable_cache_control():
    service, fake = _service()
    await service.upload_bytes(b"x", "a.webp", folder="photos", content_type="image/webp")
    assert fake.puts[0]["CacheControl"] == CACHE_CONTROL


async def test_put_sets_the_content_type_it_was_given():
    service, fake = _service()
    await service.upload_bytes(b"x", "a.webp", folder="photos", content_type="image/webp")
    assert fake.puts[0]["ContentType"] == "image/webp"


async def test_returned_url_is_the_cdn_url_for_the_key():
    service, fake = _service()
    url = await service.upload_bytes(b"x", "a.webp", folder="photos", content_type="image/webp")
    assert url.startswith(service.cdn_url)
    assert url.endswith("a.webp")
    assert fake.puts[0]["Key"] in url


async def test_delete_targets_the_key_from_the_url():
    service, fake = _service()
    await service.delete_file(f"{service.cdn_url}/flame_backend/photos/123-a.jpg")
    assert fake.deletes[0]["Key"] == "flame_backend/photos/123-a.jpg"
```

- [ ] **Step 2: Run to verify they fail**

```bash
./venv/bin/python -m pytest tests/core/test_storage.py -v
```

Expected: FAIL — `StorageService()` takes no `client` argument, and `CACHE_CONTROL` does not exist.

- [ ] **Step 3: Rewrite the I/O core of `storage.py`**

At the top of `app/core/storage.py`, add the import and constant:

```python
import asyncio

# Keys carry a millisecond timestamp and a UUID, so an object at a given key
# never changes. This is a statement of fact, not an optimistic guess.
CACHE_CONTROL = "public, max-age=31536000, immutable"
```

Change `__init__` to accept an injected client:

```python
    def __init__(self, client=None):
        # Injectable so tests can assert on calls without credentials or network.
        # `or` short-circuits, so boto3 is only constructed when no client is given.
        self.client = client or boto3.client(
            "s3",
            endpoint_url=f"https://{settings.SPACES_ENDPOINT}",
            aws_access_key_id=settings.DO_SPACES_KEY,
            aws_secret_access_key=settings.DO_SPACES_SECRET,
            config=Config(signature_version="s3v4"),
        )
```

Add one private helper that every write goes through:

```python
    async def _put(self, key: str, body: bytes, content_type: str) -> str:
        """Write one object. Threaded because boto3 is synchronous and this is
        called from async request handlers — see the module docstring."""
        await asyncio.to_thread(
            self.client.put_object,
            Bucket=self.bucket,
            Key=key,
            Body=body,
            ContentType=content_type,
            ACL="public-read",
            CacheControl=CACHE_CONTROL,
        )
        return self._fix_url(key)
```

Rewrite `upload_bytes` and `upload_file` to delegate to it, and thread the delete:

```python
    async def upload_bytes(
        self,
        data: bytes,
        filename: str,
        folder: str = "uploads",
        content_type: str = "application/octet-stream",
    ) -> str:
        return await self._put(self._build_key(folder, filename), data, content_type)

    async def upload_file(
        self,
        file: UploadFile,
        folder: str = "uploads",
        filename: Optional[str] = None,
    ) -> str:
        if not filename:
            ext = file.filename.split(".")[-1] if file.filename else "jpg"
            filename = f"{uuid.uuid4()}.{ext}"
        content = await file.read()
        await file.seek(0)
        return await self._put(
            self._build_key(folder, filename),
            content,
            file.content_type or "application/octet-stream",
        )

    async def delete_file(self, url: str) -> bool:
        try:
            key = url.replace(f"{self.cdn_url}/", "")
            await asyncio.to_thread(
                self.client.delete_object, Bucket=self.bucket, Key=key
            )
            return True
        except Exception:
            return False
```

- [ ] **Step 4: Run to verify they pass**

```bash
./venv/bin/python -m pytest tests/core/test_storage.py -v
```

Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add app/core/storage.py tests/core/test_storage.py
git commit -m "fix(storage): stop blocking the event loop on every S3 call

put_object and delete_object are synchronous boto3 calls that were being
made from async request handlers on a single uvicorn worker, so one photo
upload stalled every other request for a full round trip to Spaces.

Also sets an immutable Cache-Control, which the keys have always
justified and never carried."
```

---

## Task 6: Upload a photo as a set of variants

**Repo:** `flame_backend`

**Files:**
- Modify: `app/core/storage.py`
- Modify: `tests/core/test_storage.py`

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/test_storage.py`:

```python
import io

from PIL import Image


def _jpeg(size=(2000, 1000)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, "blue").save(buf, format="JPEG")
    return buf.getvalue()


async def test_photo_set_uploads_one_object_per_variant():
    service, fake = _service()
    await service.upload_photo_set("user1", _jpeg())
    assert len(fake.puts) == 3


async def test_photo_set_returns_a_url_per_variant():
    service, fake = _service()
    urls = await service.upload_photo_set("user1", _jpeg())
    assert set(urls) == {"full", "medium", "thumb"}
    assert all(u.startswith(service.cdn_url) for u in urls.values())


async def test_photo_set_variants_have_distinct_keys():
    service, fake = _service()
    await service.upload_photo_set("user1", _jpeg())
    keys = [p["Key"] for p in fake.puts]
    assert len(set(keys)) == 3


async def test_photo_set_uploads_webp():
    service, fake = _service()
    await service.upload_photo_set("user1", _jpeg())
    assert all(p["ContentType"] == "image/webp" for p in fake.puts)


async def test_photo_set_keys_are_namespaced_by_user():
    service, fake = _service()
    await service.upload_photo_set("user1", _jpeg())
    assert all("user1" in p["Key"] for p in fake.puts)
```

- [ ] **Step 2: Run to verify they fail**

```bash
./venv/bin/python -m pytest tests/core/test_storage.py -v -k photo_set
```

Expected: FAIL — `StorageService` has no attribute `upload_photo_set`.

- [ ] **Step 3: Implement it**

Add to `app/core/storage.py`:

```python
from app.core.images import generate_variants


    async def upload_photo_set(self, user_id: str, data: bytes) -> Dict[str, str]:
        """Generate and store every variant of one photo.

        Returns `{variant_name: cdn_url}`. Variants upload concurrently: they are
        independent objects and there is no reason to pay for them serially.
        """
        variants = generate_variants(data)
        stem = f"{user_id}-{uuid.uuid4()}"

        names = list(variants)
        keys = [self._build_key("photos", f"{stem}-{name}.webp") for name in names]
        urls = await asyncio.gather(
            *(
                self._put(key, variants[name], "image/webp")
                for name, key in zip(names, keys)
            )
        )
        return dict(zip(names, urls))
```

Add `Dict` to the `typing` import at the top of the file.

- [ ] **Step 4: Run to verify they pass**

```bash
./venv/bin/python -m pytest tests/core/test_storage.py -v
```

Expected: 11 passed.

- [ ] **Step 5: Collapse the duplicated message upload methods**

`upload_message_image`, `upload_message_video`, `upload_message_audio`, `upload_voice_message`, `upload_message_file` and `upload_video_thumbnail` are six near-identical four-line methods. They are all being touched for the threading change; six copies of the same code is where the next bug hides. Replace all six with one:

```python
    async def upload_conversation_media(
        self,
        conversation_id: str,
        file: UploadFile,
        kind: str,
        default_ext: str,
    ) -> str:
        """Store one conversation attachment. `kind` selects the folder."""
        ext = file.filename.split(".")[-1] if file.filename else default_ext
        filename = f"{conversation_id}-{uuid.uuid4()}.{ext}"
        return await self.upload_file(file, folder=f"messages/{kind}", filename=filename)
```

Then update the call sites in `app/chat/routes.py`. Find them first:

```bash
grep -rn "upload_message_\|upload_voice_message\|upload_video_thumbnail" app/
```

Map each to the new signature, preserving the exact folder each used so existing objects stay addressable:

| Old method | `kind` | `default_ext` |
|---|---|---|
| `upload_message_image` | `images` | `jpg` |
| `upload_message_video` | `videos` | `mp4` |
| `upload_message_audio` | `audio` | `mp3` |
| `upload_voice_message` | `voice` | `ogg` |
| `upload_message_file` | `files` | `bin` |
| `upload_video_thumbnail` | `thumbnails` | `jpg` |

`upload_video_thumbnail` also inserted `-thumb-` into the filename. Preserve that by passing `kind="thumbnails"` and accepting the slightly different stem; the folder is what makes it addressable.

- [ ] **Step 6: Verify imports and tests**

```bash
./venv/bin/python -c "import app.main" && ./venv/bin/python -m pytest tests/ -v
```

Expected: no import error, all tests pass.

- [ ] **Step 7: Commit**

```bash
git add app/core/storage.py app/chat/routes.py tests/core/test_storage.py
git commit -m "feat(storage): upload photos as a variant set

Variants upload concurrently. Also collapses six near-identical
upload_message_* methods into one parameterised call, preserving every
existing folder so objects already in Spaces stay addressable."
```

---

## Task 7: Wire the photo routes to variants

**Repo:** `flame_backend`

**Files:**
- Modify: `app/users/routes.py` (both photo routes and the shim from Task 4)
- Modify: `app/auth/service.py:56` (the base64 registration path)

- [ ] **Step 1: Rewrite the add-photo route**

In `app/users/routes.py`, the route that currently calls `storage.upload_user_photo(user_id, photo)` at line 123. Replace the upload block with:

```python
    data = await photo.read()
    validate_image_upload(
        photo.content_type, size=len(data), max_size=settings.MAX_PHOTO_SIZE
    )
    validate_photo_count(len(current_user.photos), maximum=settings.MAX_PHOTOS_PER_USER)

    try:
        urls = await storage.upload_photo_set(user_id, data)
    except ImageProcessingError as exc:
        raise AppException(status_code=400, code="INVALID_IMAGE", message=str(exc))

    new_photo = Photo(
        id=str(uuid.uuid4()),
        url=urls["full"],
        url_medium=urls["medium"],
        url_thumb=urls["thumb"],
        is_primary=len(current_user.photos) == 0,
        order=len(current_user.photos),
    )
```

Reading the bytes once and passing `len(data)` also removes the current read-then-seek-then-read-again pattern.

- [ ] **Step 2: Rewrite the primary-photo route the same way**

The route at line 57 (`update_profile_picture`) gets the same treatment, keeping its existing "demote the old primary" logic. Note it calls `storage.delete_file(p.url)` on the old primary — leave that behaviour alone, but be aware it now only deletes the `full` variant. Add a TODO rather than fixing it here:

```python
    # TODO: deletes only the full variant; medium/thumb are orphaned. Harmless
    # (they are small and unreferenced) but worth a sweep later.
```

- [ ] **Step 3: Give the base64 registration path the same ceiling**

`app/auth/service.py:56` calls `storage.upload_base64_image(photo_data, temp_user_id)` with no size check at all. Decode first, check, then use the variant path:

```python
            if storage.is_base64_image(photo_data):
                raw = storage.decode_base64_image(photo_data)
                validate_image_upload(
                    "image/jpeg", size=len(raw), max_size=settings.MAX_PHOTO_SIZE
                )
                urls = await storage.upload_photo_set(temp_user_id, raw)
```

This requires splitting the existing `upload_base64_image` into a pure `decode_base64_image(base64_string) -> bytes` plus the upload. Do that split in `storage.py`; the decoding logic already exists there and just needs lifting out of the upload method.

- [ ] **Step 4: Remove the Task 4 shim**

Delete the deprecated `validate_image_file` shim. Confirm nothing still calls it:

```bash
grep -rn "validate_image_file" app/
```

Expected: no results.

- [ ] **Step 5: Verify**

```bash
./venv/bin/python -c "import app.main" && ./venv/bin/python -m pytest tests/ -v
```

Expected: no import error, all tests pass.

- [ ] **Step 6: Manual smoke test against the dev stack**

```bash
make dev
```

Then upload a photo through `http://localhost:8000/docs` and confirm the response carries all three URLs. Stop with `make dev-down`.

- [ ] **Step 7: Commit**

```bash
git add app/users/routes.py app/auth/service.py app/core/storage.py
git commit -m "feat(photos): store variants on every upload path

Includes the base64 registration path, which accepted images of
unbounded size."
```

---

## Task 8: Run more than one worker

**Repo:** `flame_backend`

Safe, and checked: every outbound WebSocket message goes through `redis_pubsub.publish` and local delivery happens only inside `handle_redis_message` (`websocket.py:98`), so there is no duplicate-send. Presence is Redis-backed with a TTL (`cache.py:221`), not per-process.

**Files:**
- Modify: `Dockerfile:25`

- [ ] **Step 1: Change the command**

```dockerfile
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
```

- [ ] **Step 2: Bring the stack up and confirm four workers boot**

```bash
docker compose -f docker-compose.dev.yml up -d --build
docker compose -f docker-compose.dev.yml logs app | grep -c "Started server process"
```

Expected: `4`.

- [ ] **Step 3: Confirm chat still works across workers**

Open two WebSocket connections and send a message between them. They will usually land on different workers, which is exactly what needs proving.

```bash
docker compose -f docker-compose.dev.yml logs app | grep -i "error\|traceback"
```

Expected: no errors. A warning from `_drop_conflicting_indexes` is expected and harmless — it is conditional and try/except-wrapped, and `createIndexes` is idempotent.

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "perf: run uvicorn with 4 workers

Safe because the WebSocket layer already fans out through Redis pub/sub
and presence is Redis-backed rather than per-process. A single worker is
why blocking I/O was catastrophic rather than merely wasteful."
```

---

## Task 9: Backfill existing photos

**Repo:** `flame_backend`

**This task carries the rule that cannot be relaxed:** add variants beside the original, never rewrite `url`, never delete the object it names.

**Files:**
- Create: `tool/backfill_photo_variants.py`
- Create: `tests/tool/__init__.py`
- Create: `tests/tool/test_backfill.py`

- [ ] **Step 1: Write the failing tests**

`tests/tool/test_backfill.py`:

```python
import pytest

from tool.backfill_photo_variants import needs_variants, merged_photo


def test_a_photo_with_no_variants_needs_work():
    assert needs_variants({"url": "https://cdn/a.jpg"})


def test_a_photo_with_variants_is_skipped():
    assert not needs_variants(
        {"url": "https://cdn/a.jpg", "url_thumb": "https://cdn/a_thumb.webp"}
    )


def test_a_photo_with_an_empty_thumb_needs_work():
    assert needs_variants({"url": "https://cdn/a.jpg", "url_thumb": ""})


def test_merge_never_rewrites_the_original_url():
    # The one rule this whole script exists under: clients in the field read
    # `url` and nothing else.
    original = {"id": "p1", "url": "https://cdn/a.jpg", "is_primary": True, "order": 0}
    merged = merged_photo(
        original,
        {
            "full": "https://cdn/a-full.webp",
            "medium": "https://cdn/a-medium.webp",
            "thumb": "https://cdn/a-thumb.webp",
        },
    )
    assert merged["url"] == "https://cdn/a.jpg"


def test_merge_attaches_the_small_variants():
    original = {"id": "p1", "url": "https://cdn/a.jpg"}
    merged = merged_photo(
        original,
        {
            "full": "https://cdn/a-full.webp",
            "medium": "https://cdn/a-medium.webp",
            "thumb": "https://cdn/a-thumb.webp",
        },
    )
    assert merged["url_medium"] == "https://cdn/a-medium.webp"
    assert merged["url_thumb"] == "https://cdn/a-thumb.webp"


def test_merge_preserves_every_other_field():
    original = {"id": "p1", "url": "https://cdn/a.jpg", "is_primary": True, "order": 3}
    merged = merged_photo(original, {"full": "f", "medium": "m", "thumb": "t"})
    assert merged["id"] == "p1"
    assert merged["is_primary"] is True
    assert merged["order"] == 3


def test_merge_is_idempotent():
    original = {"id": "p1", "url": "https://cdn/a.jpg"}
    urls = {"full": "f", "medium": "m", "thumb": "t"}
    once = merged_photo(original, urls)
    twice = merged_photo(once, urls)
    assert once == twice
```

- [ ] **Step 2: Run to verify they fail**

```bash
./venv/bin/python -m pytest tests/tool/test_backfill.py -v
```

Expected: `ModuleNotFoundError: No module named 'tool'`.

- [ ] **Step 3: Write the script**

`tool/backfill_photo_variants.py`. Create `tool/__init__.py` (empty) alongside it.

```python
"""Backfill variant URLs onto photos uploaded before the variant pipeline.

Run once, after the backend deploy.

    ./venv/bin/python -m tool.backfill_photo_variants --dry-run
    ./venv/bin/python -m tool.backfill_photo_variants

Idempotent: a photo that already has `url_thumb` is skipped, so a run that dies
partway is resumed by running it again.

The original `url` is never rewritten and the object it names is never deleted.
Clients already in the field read that field and nothing else.
"""
from __future__ import annotations

import argparse
import asyncio
import logging
from typing import Dict

import httpx

from app.core.database import connect_to_mongo, close_mongo_connection
from app.core.images import ImageProcessingError
from app.core.storage import storage
from app.models.user import User

logger = logging.getLogger("backfill")


def needs_variants(photo: dict) -> bool:
    """True if this photo has no thumb yet. The thumb is the marker because it
    is the last variant written, so its presence means the set completed."""
    return not photo.get("url_thumb")


def merged_photo(photo: dict, urls: Dict[str, str]) -> dict:
    """Return `photo` with variant URLs attached. `url` is left exactly as it
    was — see the module docstring."""
    merged = dict(photo)
    merged["url_medium"] = urls["medium"]
    merged["url_thumb"] = urls["thumb"]
    return merged


async def _fetch(client: httpx.AsyncClient, url: str) -> bytes:
    response = await client.get(url, timeout=30.0)
    response.raise_for_status()
    return response.content


async def backfill(dry_run: bool = False) -> dict:
    await connect_to_mongo()
    stats = {"users": 0, "processed": 0, "skipped": 0, "failed": 0}
    try:
        async with httpx.AsyncClient() as client:
            async for user in User.find_all():
                stats["users"] += 1
                changed = False
                photos = [p.model_dump() for p in user.photos]

                for index, photo in enumerate(photos):
                    if not needs_variants(photo):
                        stats["skipped"] += 1
                        continue
                    if dry_run:
                        stats["processed"] += 1
                        continue
                    try:
                        data = await _fetch(client, photo["url"])
                        urls = await storage.upload_photo_set(str(user.id), data)
                        photos[index] = merged_photo(photo, urls)
                        changed = True
                        stats["processed"] += 1
                    except (httpx.HTTPError, ImageProcessingError, OSError) as exc:
                        # One bad photo must not stop the batch.
                        logger.warning(
                            "photo %s of user %s failed: %s", photo.get("id"), user.id, exc
                        )
                        stats["failed"] += 1

                if changed:
                    user.photos = [type(user.photos[0])(**p) for p in photos]
                    await user.save()
    finally:
        await close_mongo_connection()
    return stats


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="report what would be processed without writing anything",
    )
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    stats = asyncio.run(backfill(dry_run=args.dry_run))
    print(
        f"users={stats['users']} processed={stats['processed']} "
        f"skipped={stats['skipped']} failed={stats['failed']}"
    )


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run to verify they pass**

```bash
./venv/bin/python -m pytest tests/tool/test_backfill.py -v
```

Expected: 7 passed.

- [ ] **Step 5: Dry run against the real database**

```bash
./venv/bin/python -m tool.backfill_photo_variants --dry-run
```

Expected: a count of photos that would be processed, and zero writes. Sanity-check that `processed` roughly matches the number of photos you expect to exist.

- [ ] **Step 6: Commit**

```bash
git add tool/ tests/tool/
git commit -m "feat(images): backfill script for photos predating variants

Idempotent and resumable. Adds variants beside the original and never
rewrites url, because every client in the field reads that field and
would 404 on all photos at once."
```

---

## Task 10: Deploy 1 verification

**Repo:** `flame_backend`

- [ ] **Step 1: Full test run**

```bash
./venv/bin/python -m pytest tests/ -v
```

Expected: all tests pass. Record the count.

- [ ] **Step 2: Confirm the app boots**

```bash
./venv/bin/python -c "import app.main; print('ok')"
```

- [ ] **Step 3: Full stack smoke test**

```bash
docker compose -f docker-compose.dev.yml up -d --build
curl -sf http://localhost:8000/health && echo " health ok"
```

- [ ] **Step 4: Confirm the old client contract still holds**

This is the check that protects `1.0.0+10001`. Fetch a user through the API and confirm each photo entry still has a `url` key holding a working URL:

```bash
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8000/v1/users/me | python3 -m json.tool | grep -A4 '"photos"'
```

Expected: every entry has `url`, and `url` resolves. The new `url_medium` / `url_thumb` keys alongside it are what the old client ignores.

- [ ] **Step 5: Deploy, then backfill**

Deploy the backend. Once it is healthy, run the backfill for real:

```bash
./venv/bin/python -m tool.backfill_photo_variants
```

- [ ] **Step 6: Merge**

```bash
git checkout main && git merge image-pipeline
```

**STOP HERE.** Deploy 1 is complete and in production. Tasks 11-17 are the app and ship separately.

---

# DEPLOY 2 — APP

**Repo for every task below:** `/Users/davis/Desktop/Personal/flame`

Do not start until Deploy 1 is in production and the backfill has run. These tasks assume the API returns `url_medium` and `url_thumb`.

Run tests with `flutter test`. A single file: `flutter test test/path/to/file_test.dart`.

---

## Task 11: A Photo model that carries its variants

**Files:**
- Create: `lib/models/photo.dart`
- Create: `lib/core/image/photo_variants.dart`
- Modify: `lib/services/user_service.dart:225-243` (delete the local `Photo`, re-export)
- Modify: `lib/models/models.dart` (export the new model)
- Create: `test/models/photo_test.dart`
- Create: `test/core/image/photo_variants_test.dart`

`Photo` already exists at `user_service.dart:225` with `id`, `url`, `isPrimary`, `order`. It is a model living in a service file. Rather than inventing a second type beside it, move it to `lib/models/` and give it the variant fields — one type, in the right place.

- [ ] **Step 1: Write the failing tests**

`test/models/photo_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/photo.dart';

void main() {
  group('Photo.fromJson', () {
    test('reads a full object with variants', () {
      final photo = Photo.fromJson({
        'id': 'p1',
        'url': 'https://cdn/a.jpg',
        'url_medium': 'https://cdn/a-medium.webp',
        'url_thumb': 'https://cdn/a-thumb.webp',
        'is_primary': true,
        'order': 2,
      });

      expect(photo.id, 'p1');
      expect(photo.url, 'https://cdn/a.jpg');
      expect(photo.urlMedium, 'https://cdn/a-medium.webp');
      expect(photo.urlThumb, 'https://cdn/a-thumb.webp');
      expect(photo.isPrimary, isTrue);
      expect(photo.order, 2);
    });

    test('reads an object that predates variants', () {
      final photo = Photo.fromJson({'id': 'p1', 'url': 'https://cdn/a.jpg'});
      expect(photo.urlMedium, isNull);
      expect(photo.urlThumb, isNull);
    });

    test('reads a bare URL string', () {
      // The API has historically returned both shapes; User.fromJson already
      // handles it and the model must too.
      final photo = Photo.fromJson('https://cdn/a.jpg');
      expect(photo.url, 'https://cdn/a.jpg');
      expect(photo.id, isEmpty);
    });

    test('returns null for an entry with no usable url', () {
      expect(Photo.tryFromJson({'id': 'p1'}), isNull);
      expect(Photo.tryFromJson({'id': 'p1', 'url': ''}), isNull);
      expect(Photo.tryFromJson(42), isNull);
    });
  });
}
```

`test/core/image/photo_variants_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/image/photo_variants.dart';
import 'package:flame/models/photo.dart';

Photo _photo({String? medium, String? thumb}) => Photo(
      id: 'p1',
      url: 'https://cdn/full.jpg',
      urlMedium: medium,
      urlThumb: thumb,
    );

void main() {
  group('photoUrlFor', () {
    test('picks the exact variant when it exists', () {
      final photo = _photo(medium: 'https://cdn/m.webp', thumb: 'https://cdn/t.webp');
      expect(photoUrlFor(photo, PhotoSize.thumb), 'https://cdn/t.webp');
      expect(photoUrlFor(photo, PhotoSize.medium), 'https://cdn/m.webp');
      expect(photoUrlFor(photo, PhotoSize.full), 'https://cdn/full.jpg');
    });

    test('falls back down the ladder, never up', () {
      // A photo the backfill has not reached yet. Serving the full image is
      // slow; serving nothing is broken.
      final photo = _photo(medium: 'https://cdn/m.webp');
      expect(photoUrlFor(photo, PhotoSize.thumb), 'https://cdn/m.webp');
    });

    test('falls all the way back to the original', () {
      final photo = _photo();
      expect(photoUrlFor(photo, PhotoSize.thumb), 'https://cdn/full.jpg');
      expect(photoUrlFor(photo, PhotoSize.medium), 'https://cdn/full.jpg');
    });

    test('treats an empty variant as absent', () {
      final photo = _photo(thumb: '');
      expect(photoUrlFor(photo, PhotoSize.thumb), 'https://cdn/full.jpg');
    });
  });
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
flutter test test/models/photo_test.dart test/core/image/photo_variants_test.dart
```

Expected: compile error — `lib/models/photo.dart` does not exist.

- [ ] **Step 3: Write the model**

`lib/models/photo.dart`:

```dart
/// One profile photo and its sized variants.
///
/// [url] is the full-size image and is always present. [urlMedium] and
/// [urlThumb] are null for photos uploaded before the variant pipeline, and for
/// photos the backfill has not reached — callers must go through
/// `photoUrlFor` rather than reading a variant field directly.
class Photo {
  const Photo({
    required this.id,
    required this.url,
    this.urlMedium,
    this.urlThumb,
    this.isPrimary = false,
    this.order = 0,
  });

  final String id;
  final String url;
  final String? urlMedium;
  final String? urlThumb;
  final bool isPrimary;
  final int order;

  /// Parses an entry that may be an object or a bare URL string.
  /// Throws if there is no usable URL; use [tryFromJson] when that is possible.
  factory Photo.fromJson(dynamic raw) {
    final photo = tryFromJson(raw);
    if (photo == null) {
      throw ArgumentError('photo entry has no usable url: $raw');
    }
    return photo;
  }

  /// Null when [raw] carries no usable URL, so a malformed entry can be dropped
  /// rather than crashing a profile.
  static Photo? tryFromJson(dynamic raw) {
    if (raw is String) {
      return raw.isEmpty ? null : Photo(id: '', url: raw);
    }
    if (raw is! Map) return null;

    final url = raw['url']?.toString() ?? '';
    if (url.isEmpty) return null;

    String? optional(String key) {
      final value = raw[key]?.toString();
      return (value == null || value.isEmpty) ? null : value;
    }

    return Photo(
      id: raw['id']?.toString() ?? '',
      url: url,
      urlMedium: optional('url_medium'),
      urlThumb: optional('url_thumb'),
      isPrimary: raw['is_primary'] == true,
      order: raw['order'] is int ? raw['order'] as int : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Photo &&
      other.id == id &&
      other.url == url &&
      other.urlMedium == urlMedium &&
      other.urlThumb == urlThumb &&
      other.isPrimary == isPrimary &&
      other.order == order;

  @override
  int get hashCode => Object.hash(id, url, urlMedium, urlThumb, isPrimary, order);
}
```

`lib/core/image/photo_variants.dart`:

```dart
import 'package:flame/models/photo.dart';

/// The variant to request. Named for the surface, not the pixel count, so call
/// sites read as intent rather than as a number to second-guess.
enum PhotoSize {
  /// 256px long edge — avatars, matches grid, chat rows.
  thumb,

  /// 512px long edge — edit-profile grid, previews.
  medium,

  /// 1440px long edge — deck cards, profile detail, gallery, media viewer.
  full,
}

/// The best available URL at or above [size].
///
/// Falls back down the ladder — thumb to medium to full — never up. A photo the
/// backfill has not reached yet has no variants at all, and serving a slow
/// image beats serving a broken one.
String photoUrlFor(Photo photo, PhotoSize size) {
  return switch (size) {
    PhotoSize.thumb => photo.urlThumb ?? photo.urlMedium ?? photo.url,
    PhotoSize.medium => photo.urlMedium ?? photo.url,
    PhotoSize.full => photo.url,
  };
}
```

- [ ] **Step 4: Run to verify they pass**

```bash
flutter test test/models/photo_test.dart test/core/image/photo_variants_test.dart
```

Expected: all pass.

- [ ] **Step 5: Delete the old Photo and re-point its users**

In `lib/services/user_service.dart`, delete the `Photo` class (lines 225-243 plus its `fromJson`) and add at the top:

```dart
import 'package:flame/models/photo.dart';
export 'package:flame/models/photo.dart' show Photo;
```

The `export` keeps `import 'package:flame/services/user_service.dart' show Photo;` working at existing call sites, so this step compiles on its own.

Add the model to the barrel file `lib/models/models.dart`:

```dart
export 'photo.dart';
```

- [ ] **Step 6: Verify the whole suite still compiles**

```bash
flutter analyze && flutter test
```

Expected: no analyzer errors, 143+ tests pass.

- [ ] **Step 7: Commit**

```bash
git checkout -b image-pipeline-app
git add lib/models/photo.dart lib/core/image/photo_variants.dart \
        lib/services/user_service.dart lib/models/models.dart \
        test/models/photo_test.dart test/core/image/photo_variants_test.dart
git commit -m "feat(images): Photo model carries its variant URLs

Moves the existing Photo out of user_service.dart, where a model had no
business living, and gives it url_medium/url_thumb. photoUrlFor is the
only thing that knows the fallback ladder."
```

---

## Task 12: `User.photos` becomes a list of Photos

**Files:**
- Modify: `lib/models/user.dart:14-17`, `:121-142`, `:169`, `:262`, `:293-294`
- Modify: `lib/providers/user_provider.dart:101-102`, `:126-135`, `:150-164`, `:173-187`
- Modify: `lib/screens/profile/my_profile_screen.dart`, `lib/screens/profile/profile_detail_screen.dart`, `lib/screens/profile/edit_profile/photos_section.dart`, `lib/widgets/profile_card.dart`
- Modify: `test/models/user_*_test.dart` and any test constructing a `User` with photos
- Create: `test/models/user_photos_test.dart`

Today `User` holds two index-aligned lists, `photos` (`List<String>`) and `photoIds` (`List<String>`), with a comment conceding that a photo arriving as a bare URL gets an empty-string id. Adding two more aligned lists for the variants would make four. One list of objects removes the alignment problem instead of doubling it.

- [ ] **Step 1: Write the failing test**

`test/models/user_photos_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';

void main() {
  group('User.fromJson photos', () {
    test('parses objects with variants', () {
      final user = User.fromJson({
        'id': 'u1',
        'name': 'Ada',
        'photos': [
          {
            'id': 'p1',
            'url': 'https://cdn/a.jpg',
            'url_thumb': 'https://cdn/a-thumb.webp',
          },
        ],
      });

      expect(user.photos, hasLength(1));
      expect(user.photos.first.id, 'p1');
      expect(user.photos.first.urlThumb, 'https://cdn/a-thumb.webp');
    });

    test('parses bare URL strings', () {
      final user = User.fromJson({
        'id': 'u1',
        'name': 'Ada',
        'photos': ['https://cdn/a.jpg'],
      });
      expect(user.photos.first.url, 'https://cdn/a.jpg');
    });

    test('drops entries with no usable url', () {
      final user = User.fromJson({
        'id': 'u1',
        'name': 'Ada',
        'photos': [
          {'id': 'p1'},
          {'id': 'p2', 'url': 'https://cdn/b.jpg'},
          42,
        ],
      });
      expect(user.photos, hasLength(1));
      expect(user.photos.first.id, 'p2');
    });

    test('photoIds stays available and stays aligned', () {
      final user = User.fromJson({
        'id': 'u1',
        'name': 'Ada',
        'photos': [
          {'id': 'p1', 'url': 'https://cdn/a.jpg'},
          {'id': 'p2', 'url': 'https://cdn/b.jpg'},
        ],
      });
      expect(user.photoIds, ['p1', 'p2']);
    });

    test('handles a missing photos key', () {
      final user = User.fromJson({'id': 'u1', 'name': 'Ada'});
      expect(user.photos, isEmpty);
      expect(user.photoIds, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/models/user_photos_test.dart
```

Expected: compile error — `user.photos.first.id` on a `String`.

- [ ] **Step 3: Change the field**

In `lib/models/user.dart`, replace the two aligned lists:

```dart
  final List<Photo> photos;

  /// Backend photo ids, in photo order. Derived rather than stored: it used to
  /// be a second list held in step with [photos], which is a class of bug this
  /// removes rather than manages.
  List<String> get photoIds => photos.map((p) => p.id).toList();
```

Delete `photoIds` from the constructor and from `copyWith` (both the parameter at `:262` and the assignment at `:294`).

Replace the photo-parsing block in `fromJson` (currently lines 122-142) with:

```dart
    final rawPhotos = json['photos'];
    final photos = rawPhotos is List
        ? rawPhotos
            .map(Photo.tryFromJson)
            .whereType<Photo>()
            .toList()
        : <Photo>[];
```

and pass `photos: photos` in the constructor call, removing `photoIds: photoIdList`.

Add the import: `import 'package:flame/models/photo.dart';`

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/models/user_photos_test.dart
```

Expected: 5 passed.

- [ ] **Step 5: Fix every call site the analyzer names**

```bash
flutter analyze
```

Work through the errors. The expected set, and what each becomes:

| Site | Change |
|---|---|
| `user_provider.dart:101` | `photos: [...currentUser.photos, Photo(id: result.data!.id, url: result.data!.url, urlMedium: result.data!.urlMedium, urlThumb: result.data!.urlThumb)]` — and drop the `photoIds:` argument |
| `user_provider.dart:102`, `:135`, `:164`, `:187` | delete the `photoIds:` arguments; it is a getter now |
| `user_provider.dart:127`, `:174` | `currentUser.photos[index].id` |
| `my_profile_screen.dart:111`, `:240` | pass `user.photos` through; change `openPhotoGallery` (`photo_gallery.dart:11`) from `List<String>` to `List<Photo>`, mapping with `photoUrlFor(p, PhotoSize.full)` before it builds `MediaViewerArgs` |
| `my_profile_screen.dart:115` | leave it failing to compile — Task 14 converts this avatar to `avatarProviderFor` |
| `profile_detail_screen.dart:87` | `photoUrlFor(widget.user.photos[index], PhotoSize.full)` |
| `photos_section.dart:80` | `photoUrlFor(user.photos[index], PhotoSize.medium)` |
| `photos_section.dart:143` | pass `widget.user.photos` |
| `profile_card.dart:88` | `photoUrlFor(widget.user.photos[...], PhotoSize.full)` |

`lib/screens/profile/photo_gallery.dart` will need its parameter type changed to `List<Photo>`.

Update `lib/services/user_service.dart`'s `Photo.fromJson` usages so `uploadPhoto` returns the variant fields too — the upload response now carries them.

- [ ] **Step 6: Fix the existing tests**

Several tests construct a `User` with `photos: ['url']` or pass `photoIds:`. Find them:

```bash
grep -rln "photoIds\|photos: \[" test/
```

Update each to build `Photo` objects. Tests that used `User.fromJson` with a `photos` list of strings need no change — that shape still parses.

- [ ] **Step 7: Verify**

```bash
flutter analyze && flutter test
```

Expected: clean analyze, all tests pass.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(user): photos is a list of Photo, not two aligned lists

photoIds becomes a getter derived from photos. The aligned-list pattern
already had a documented hole — a bare-URL photo got an empty-string id —
and the variants would have made it four lists instead of two."
```

---

## Task 13: `SmartImage` decodes at draw size

**Files:**
- Modify: `lib/widgets/smart_image.dart`
- Modify: `lib/widgets/profile_card.dart:86`, `lib/screens/profile/profile_detail_screen.dart:86`, `lib/screens/profile/my_profile_screen.dart:419`, `lib/screens/profile/edit_profile/photos_section.dart:100` and `:146`, `lib/screens/stories/story_viewer_screen.dart:142`
- Create: `test/widgets/smart_image_test.dart`

`smart_image.dart:56` builds a `CachedNetworkImage` with no `memCacheWidth`, so every image decodes at full resolution — roughly 4MB of RAM to fill a 64pt circle. `lib/core/image/avatar_provider.dart` already fixed this for chat avatars and documents why the parameter is required rather than optional: it makes the un-sized version unavailable instead of merely discouraged. Same reasoning here.

- [ ] **Step 1: Write the failing test**

`test/widgets/smart_image_test.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/widgets/smart_image.dart';

void main() {
  testWidgets('passes a decode width derived from the draw width and DPR',
      (tester) async {
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(
        width: 100,
        height: 100,
        child: SmartImage(
          imageSource: 'https://cdn/a.webp',
          decodeWidth: 100,
        ),
      ),
    ));

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    // Physical pixels: what the device rasterises, not what layout calls it.
    expect(image.memCacheWidth, 300);
  });

  testWidgets('renders a data URI without hitting the network',
      (tester) async {
    const onePixelPng =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

    await tester.pumpWidget(const MaterialApp(
      home: SmartImage(imageSource: onePixelPng, decodeWidth: 100),
    ));

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/widgets/smart_image_test.dart
```

Expected: compile error — `SmartImage` has no `decodeWidth` parameter.

- [ ] **Step 3: Add the parameter**

In `lib/widgets/smart_image.dart`, add a required field and use it:

```dart
  /// The width this image will actually be drawn at, in logical pixels.
  ///
  /// Required rather than optional, deliberately: an unsized decode holds a
  /// full-resolution bitmap to fill a thumbnail, and making the slow version
  /// merely discouraged did not work — every call site outside chat had it.
  /// See `core/image/avatar_provider.dart`, which made the same call.
  final double decodeWidth;
```

Add `required this.decodeWidth` to the constructor, then in `_buildNetworkImage`:

```dart
  Widget _buildNetworkImage(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return CachedNetworkImage(
      imageUrl: imageSource,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: (decodeWidth * dpr).round(),
      placeholder: (context, url) => placeholder ?? _defaultPlaceholder(),
      errorWidget: (context, url, error) => errorWidget ?? _defaultErrorWidget(),
    );
  }
```

`build` must pass `context` down to it.

Also give the base64 branch a decode ceiling — `Image.memory` has `cacheWidth`:

```dart
      return Image.memory(
        bytes,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: (decodeWidth * dpr).round(),
        errorBuilder: ...
      );
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/widgets/smart_image_test.dart
```

Expected: 2 passed.

- [ ] **Step 5: Fix the six call sites**

```bash
flutter analyze
```

Each named site gets a `decodeWidth` matching what it draws, and the right variant:

| Site | `decodeWidth` | Variant |
|---|---|---|
| `profile_card.dart:86` | `MediaQuery.sizeOf(context).width` | `PhotoSize.full` |
| `profile_detail_screen.dart:86` | `MediaQuery.sizeOf(context).width` | `PhotoSize.full` |
| `my_profile_screen.dart:419` | the tile's width | `PhotoSize.medium` |
| `photos_section.dart:100` | the tile's width | `PhotoSize.medium` |
| `photos_section.dart:146` | the tile's width | `PhotoSize.medium` |
| `story_viewer_screen.dart:142` | `MediaQuery.sizeOf(context).width` | `PhotoSize.full` |

- [ ] **Step 6: Verify**

```bash
flutter analyze && flutter test
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "perf(images): SmartImage decodes at draw size

Required parameter, not optional. avatar_provider.dart fixed exactly this
bug for chat avatars and made the same call for the same reason: every
site that could skip it, did."
```

---

## Task 14: The avatar sites that were never fixed

**Files:**
- Modify: `lib/core/image/avatar_provider.dart`
- Modify: `lib/screens/discover/discover_screen.dart:189`
- Modify: `lib/screens/chat/matches_screen.dart:314`, `:414`
- Modify: `lib/screens/profile/my_profile_screen.dart:115`
- Create: `test/core/image/avatar_provider_test.dart`

**Read this before starting.** `AppAvatar` (`lib/widgets/kit/app_avatar.dart`) looks like the avatar widget and is not — its only call site is inside its own file. Do not spend time on it.

The real avatar rendering is raw `CircleAvatar` with a `backgroundImage`, and it splits into two groups:

*Already correct*, using the `avatarProvider` helper that exists precisely for this:
- `chat_app_bar.dart:57`
- `conversation_empty_state.dart:33`

*Still on the unfixed path*, decoding a full-size photo to fill a small circle:
- `discover_screen.dart:189` — `NetworkImage(user.primaryPhoto)`. Not merely unsized: a raw `NetworkImage` has no disk cache at all, so this refetches on every rebuild.
- `matches_screen.dart:314` — `toImageProvider()`, `radius: 32`
- `matches_screen.dart:414` — `toImageProvider()`, `radius: 28`
- `my_profile_screen.dart:115` — `toImageProvider()`

`avatar_provider.dart` was written to fix exactly this and was scoped to chat. This task finishes the job it started.

- [ ] **Step 1: Write the failing test**

`test/core/image/avatar_provider_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/image/avatar_provider.dart';
import 'package:flame/models/photo.dart';

Photo _photo({String? thumb}) =>
    Photo(id: 'p1', url: 'https://cdn/full.jpg', urlThumb: thumb);

void main() {
  test('returns null for a photo-less user', () {
    expect(avatarProviderFor(null, diameter: 64, devicePixelRatio: 3), isNull);
  });

  test('resizes to the physical diameter', () {
    final provider = avatarProviderFor(
      _photo(thumb: 'https://cdn/t.webp'),
      diameter: 64,
      devicePixelRatio: 3,
    );
    expect(provider, isA<ResizeImage>());
    expect((provider! as ResizeImage).width, 192);
  });

  test('prefers the thumb variant', () {
    final provider = avatarProviderFor(
      _photo(thumb: 'https://cdn/t.webp'),
      diameter: 64,
      devicePixelRatio: 1,
    ) as ResizeImage;
    expect(provider.imageProvider.toString(), contains('t.webp'));
  });

  test('falls back to the full image when no variant exists', () {
    final provider = avatarProviderFor(
      _photo(),
      diameter: 64,
      devicePixelRatio: 1,
    ) as ResizeImage;
    expect(provider.imageProvider.toString(), contains('full.jpg'));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/core/image/avatar_provider_test.dart
```

Expected: FAIL — `avatarProviderFor` is not defined.

- [ ] **Step 3: Add the Photo-aware entry point**

In `lib/core/image/avatar_provider.dart`, keep the existing string-based `avatarProvider` (two call sites already use it) and add a `Photo`-aware sibling:

```dart
/// [avatarProvider] for a [Photo], picking the thumb variant.
///
/// Prefer this over the string form: passing a URL means the caller has already
/// chosen a variant, and at avatar size that choice is always the thumb.
ImageProvider? avatarProviderFor(
  Photo? photo, {
  required double diameter,
  required double devicePixelRatio,
}) {
  if (photo == null) return null;
  return avatarProvider(
    photoUrlFor(photo, PhotoSize.thumb),
    diameter: diameter,
    devicePixelRatio: devicePixelRatio,
  );
}
```

Import `photo.dart` and `photo_variants.dart`.

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/core/image/avatar_provider_test.dart
```

Expected: 4 passed.

- [ ] **Step 5: Give `User` a Photo-typed primary**

`user.dart:321` currently reads `String get primaryPhoto => photos.isNotEmpty ? photos.first : ''`. After Task 12 `photos.first` is a `Photo`, so this no longer compiles. Replace it:

```dart
  /// The photo shown wherever one photo stands for the user. Null when they
  /// have none — callers must handle that rather than receive an empty string
  /// that fails later at the image layer.
  Photo? get primaryPhoto => photos.isEmpty ? null : photos.first;
```

The analyzer will name every consumer. `chat_screen.dart:175`, `:182` and `story_tray.dart:49` pass a URL string onward to widgets that expect one — give those `photoUrlFor(user.primaryPhoto!, PhotoSize.thumb)` guarded by a null check, rather than changing those widgets' signatures.

- [ ] **Step 6: Convert the four unfixed sites**

```dart
// discover_screen.dart:189 — was NetworkImage(user.primaryPhoto), which had no
// disk cache and refetched on every rebuild.
backgroundImage: avatarProviderFor(
  user.primaryPhoto,
  diameter: 40,  // match the CircleAvatar's radius * 2
  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
),
```

Same shape for `matches_screen.dart:314` (`diameter: 64`), `matches_screen.dart:414` (`diameter: 56`) and `my_profile_screen.dart:115` (use that avatar's actual radius doubled). Read each `CircleAvatar`'s `radius` and pass twice that as `diameter`.

- [ ] **Step 7: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "perf(images): finish the avatar fix outside chat

avatar_provider.dart was written for this bug and scoped to chat avatars.
The matches grid, chat rows, discover header and own-profile avatar were
all still decoding a full-size photo into a small circle, and the
discover one used a raw NetworkImage with no disk cache at all."
```

## Task 15: The deck prefetches the next cards

**Files:**
- Modify: `lib/screens/discover/discover_screen.dart` (`_onSwipe` at `:61`, plus the initial load)
- Create: `test/screens/discover/deck_prefetch_test.dart`

Card N+1's image currently begins downloading when it becomes visible, which is the moment it is too late.

- [ ] **Step 1: Write the failing test**

`test/screens/discover/deck_prefetch_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/photo.dart';
import 'package:flame/models/user.dart';
import 'package:flame/screens/discover/deck_prefetch.dart';

User _user(String id) => User.fromJson({
      'id': id,
      'name': 'U$id',
      'photos': [
        {'id': 'p$id', 'url': 'https://cdn/$id.jpg'}
      ],
    });

void main() {
  group('urlsToPrefetch', () {
    test('takes the primary photo of the next two cards', () {
      final deck = [_user('1'), _user('2'), _user('3'), _user('4')];
      expect(
        urlsToPrefetch(deck, currentIndex: 0),
        ['https://cdn/2.jpg', 'https://cdn/3.jpg'],
      );
    });

    test('stops cleanly at the end of the deck', () {
      final deck = [_user('1'), _user('2')];
      expect(urlsToPrefetch(deck, currentIndex: 1), isEmpty);
    });

    test('skips cards with no photos', () {
      final deck = [
        _user('1'),
        User.fromJson({'id': '2', 'name': 'U2', 'photos': <dynamic>[]}),
        _user('3'),
      ];
      expect(urlsToPrefetch(deck, currentIndex: 0), ['https://cdn/3.jpg']);
    });

    test('handles an empty deck', () {
      expect(urlsToPrefetch(const <User>[], currentIndex: 0), isEmpty);
    });
  });
}
```

Extracting the selection into a pure function is what makes this testable — `precacheImage` needs a real element tree and a network, and neither belongs in a unit test.

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/screens/discover/deck_prefetch_test.dart
```

Expected: compile error — `deck_prefetch.dart` does not exist.

- [ ] **Step 3: Write the helper**

`lib/screens/discover/deck_prefetch.dart`:

```dart
import 'package:flame/core/image/photo_variants.dart';
import 'package:flame/models/user.dart';

/// How many cards ahead of the visible one to warm.
///
/// Two, not more: the deck refills at three remaining
/// (`DiscoveryNotifier.refillThreshold`), so warming further ahead would fetch
/// images for cards that may never be reached.
const int kPrefetchDepth = 2;

/// The image URLs worth warming, given the card currently on top.
///
/// Pure so it can be tested without an element tree — `precacheImage` needs
/// both a real context and a network.
List<String> urlsToPrefetch(List<User> deck, {required int currentIndex}) {
  final urls = <String>[];
  for (var i = currentIndex + 1; i <= currentIndex + kPrefetchDepth; i++) {
    if (i < 0 || i >= deck.length) break;
    final photos = deck[i].photos;
    if (photos.isEmpty) continue;
    urls.add(photoUrlFor(photos.first, PhotoSize.full));
  }
  return urls;
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/screens/discover/deck_prefetch_test.dart
```

Expected: 4 passed.

- [ ] **Step 5: Call it from the screen**

In `lib/screens/discover/discover_screen.dart`, add:

```dart
  void _prefetchAhead(List<User> deck, int currentIndex) {
    for (final url in urlsToPrefetch(deck, currentIndex: currentIndex)) {
      // Fire and forget: a failed prefetch costs nothing, and the card's own
      // CachedNetworkImage will retry when it is actually shown.
      precacheImage(CachedNetworkImageProvider(url), context)
          .catchError((_) {});
    }
  }
```

Call it in two places — at the end of `_onSwipe` (line ~87), using `currentIndex ?? previousIndex + 1`, and once after the first deck load so the second card is warm before the first swipe.

- [ ] **Step 6: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "perf(discover): warm the next two cards' images

Selection logic is pure and tested; the precache call is the only part
that needs a context."
```

---

## Task 16: Cap what gets uploaded

**Files:**
- Modify: `lib/screens/auth/registration/steps/step_photos.dart:469-474`
- Modify: `lib/screens/profile/edit_profile/photos_section.dart:288-293`, `:304-309`
- Modify: `lib/screens/chat/chat_attachments.dart:42`, `:44`
- Create: `lib/core/image/upload_limits.dart`
- Create: `test/core/image/upload_limits_test.dart`

Profile photos are capped at 1024x1024, which the deck now upscales — a full-bleed card at 3x needs ~1170px. Chat images have `imageQuality: 85` and no dimension cap at all, so a 12MP camera photo uploads at 12MP.

- [ ] **Step 1: Write the failing test**

`test/core/image/upload_limits_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/image/upload_limits.dart';

void main() {
  test('profile uploads are large enough for a 3x full-bleed card', () {
    // A card is roughly the screen width; the largest common phone is ~430pt,
    // which at 3x is 1290 physical pixels.
    expect(kProfilePhotoMaxEdge, greaterThanOrEqualTo(1290));
  });

  test('profile uploads stay within the server ceiling', () {
    // MAX_PHOTO_SIZE is 10MB; 1440px at q85 is far below it, but the constant
    // should not drift upward without someone noticing.
    expect(kProfilePhotoMaxEdge, lessThanOrEqualTo(2048));
  });

  test('chat images are capped at all', () {
    expect(kChatImageMaxEdge, greaterThan(0));
    expect(kChatImageMaxEdge, lessThanOrEqualTo(kProfilePhotoMaxEdge));
  });

  test('quality is set once, not per call site', () {
    expect(kUploadQuality, inInclusiveRange(70, 90));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/core/image/upload_limits_test.dart
```

Expected: compile error.

- [ ] **Step 3: Write the constants**

`lib/core/image/upload_limits.dart`:

```dart
/// Upload dimension caps, in logical pixels on the long edge.
///
/// One home for them, because they were previously repeated at four call sites
/// with three different answers — and one call site with no answer at all.

/// Profile photos.
///
/// 1440 rather than the previous 1024: a full-bleed deck card is roughly the
/// screen width, which on a large phone at 3x is ~1290 physical pixels, so 1024
/// was being upscaled on the surface that matters most. The server generates
/// the smaller variants from this, so raising it costs one upload and improves
/// every derived size.
const int kProfilePhotoMaxEdge = 1440;

/// Chat image attachments.
///
/// Previously uncapped — `imageQuality: 85` alone still ships a 12MP camera
/// photo at 12MP. Smaller than a profile photo because a chat bubble draws at
/// `kChatMediaWidth` (240pt) and the image is never shown full-bleed except in
/// the media viewer.
const int kChatImageMaxEdge = 1280;

/// JPEG quality for every pick. The server re-encodes to WebP anyway, so this
/// only governs what crosses the wire on upload.
const int kUploadQuality = 85;
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/core/image/upload_limits_test.dart
```

- [ ] **Step 5: Use them at all four call sites**

`step_photos.dart:469` and `photos_section.dart:288` and `:304`:

```dart
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: kProfilePhotoMaxEdge.toDouble(),
        maxHeight: kProfilePhotoMaxEdge.toDouble(),
        imageQuality: kUploadQuality,
      );
```

`chat_attachments.dart:42` and `:44` — these currently pass no dimensions at all:

```dart
    ChatAttachmentKind.gallery => await p.pickImage(
        source: ImageSource.gallery,
        maxWidth: kChatImageMaxEdge.toDouble(),
        maxHeight: kChatImageMaxEdge.toDouble(),
        imageQuality: kUploadQuality,
      ),
    ChatAttachmentKind.camera => await p.pickImage(
        source: ImageSource.camera,
        maxWidth: kChatImageMaxEdge.toDouble(),
        maxHeight: kChatImageMaxEdge.toDouble(),
        imageQuality: kUploadQuality,
      ),
```

Leave `pickVideo` alone — video is out of scope.

- [ ] **Step 6: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "perf(uploads): one home for the dimension caps

Raises profile photos to 1440 because the deck card was upscaling 1024,
and caps chat images, which had no dimension limit at all."
```

---

## Task 17: Deploy 2 verification

- [ ] **Step 1: Full suite**

```bash
flutter analyze && flutter test
```

Expected: clean analyze, all tests pass. Compare the count against the 143 you started with — it should be higher, and nothing should have been deleted to make it pass.

- [ ] **Step 2: Run the app against production**

```bash
flutter run --release
```

- [ ] **Step 3: Walk the four reported surfaces**

Confirm by eye, on a real device rather than a simulator:

- **Swipe deck** — the next card's photo is already there when you swipe to it, not a spinner.
- **Matches grid and chat list** — avatars appear together, not one at a time.
- **Profile screens** — the gallery scrolls without stutter.
- **Photo upload** — completes without freezing the rest of the app.

- [ ] **Step 4: Check a pre-backfill account**

Sign in as an account whose photos existed before Deploy 1 and confirm the images still render. This exercises the fallback path in `photoUrlFor` and is the check that catches a broken backfill.

- [ ] **Step 5: Merge and ship**

```bash
git checkout main && git merge image-pipeline-app
```

Bump the version in `pubspec.yaml`, then build and submit. `test/config/app_version_test.dart` will fail the build if `lib/config/app_version.dart` is not bumped to match.

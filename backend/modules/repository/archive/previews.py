"""Small authenticated previews, generated on demand without changing uploads.

The listing and this endpoint share publication queries. Authorization is checked
before even a cached image is returned, including after a file is restricted.
"""
import hashlib
from contextlib import closing
import io
import logging
import re
import subprocess
import tempfile
import threading
from pathlib import Path

from django.core.cache import cache
from django.http import Http404

from .services import (
    capstone_entry_payload, capstone_visible_queryset,
    pit_queryset, pit_visible_deliverables_queryset,
)

logger = logging.getLogger(__name__)
_pdf_lock = threading.Lock()  # PDFium must not be called concurrently.
_render_slots = threading.BoundedSemaphore(2)
_video_extensions = {'.mp4', '.mov', '.webm', '.m4v', '.avi', '.mkv'}


def published_preview_file(target_id, user):
    if getattr(user, 'is_guest_panelist', False):
        raise Http404('Output not found.')
    match = re.fullmatch(r'(pit-deliverable|capstone|pit)-(\d+)(?:-(\d+))?', target_id)
    if not match:
        raise Http404('Output not found.')
    kind, source_id, file_id = match.groups()
    if kind == 'pit':
        entry = pit_queryset().filter(pk=source_id).first() if not file_id else None
        source = entry.file if entry else None
    else:
        queryset = pit_visible_deliverables_queryset() if kind == 'pit-deliverable' else capstone_visible_queryset()
        entry = queryset.filter(pk=source_id).first()
        payload = next((row for row in capstone_entry_payload(entry) if row['id'] == target_id), None) if entry else None
        source = None
        if payload:
            source = next((f.file for f in entry.files.all() if f.pk == payload['file_id']), None) if payload['file_id'] else entry.file
    if not source or not source.storage.exists(source.name):
        raise Http404('Output not found.')
    return source


def _jpeg(image):
    from PIL import Image, ImageOps
    if image.width * image.height > 24_000_000:
        return None
    image = ImageOps.exif_transpose(image)
    image.thumbnail((480, 640), Image.Resampling.LANCZOS)
    # A light page remains readable in both app themes; preserve alpha on white.
    if image.mode in ('RGBA', 'LA') or 'transparency' in image.info:
        rgba = image.convert('RGBA')
        base = Image.new('RGB', image.size, 'white')
        base.paste(rgba, mask=rgba.getchannel('A'))
        image = base
    else:
        image = image.convert('RGB')
    output = io.BytesIO()
    image.save(output, format='JPEG', quality=82)
    return output.getvalue()


def _video_preview(source):
    import imageio_ffmpeg
    # Storage may be remote. FFmpeg only reads this bounded local copy, never URLs.
    with tempfile.TemporaryDirectory(prefix='defensys-preview-') as folder:
        video_path = Path(folder) / ('source' + Path(source.name).suffix.lower())
        try:
            video_path = Path(source.path)
        except (NotImplementedError, AttributeError):
            with source.open('rb') as video, video_path.open('wb') as output:
                for chunk in video.chunks():
                    output.write(chunk)
        result = subprocess.run(
            [imageio_ffmpeg.get_ffmpeg_exe(), '-nostdin', '-v', 'error',
             '-protocol_whitelist', 'file,pipe', '-i', str(video_path),
             '-an', '-sn', '-dn', '-frames:v', '1',
             '-vf', 'thumbnail=30,scale=480:320:force_original_aspect_ratio=decrease',
             '-f', 'image2pipe', '-vcodec', 'mjpeg', 'pipe:1'],
            capture_output=True, timeout=12, check=True,
            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0),
        )
        return result.stdout or None


def preview_bytes(source):
    from PIL import Image
    extension = Path(source.name).suffix.lower()
    size = source.size
    if size > (512 * 1024 * 1024 if extension in _video_extensions else 32 * 1024 * 1024):
        return None
    stamp = (getattr(source.instance, 'updated_at', ''), getattr(source.instance, 'uploaded_at', ''))
    # Uploads/replacements invalidate the thumbnail even when filenames repeat.
    fingerprint = f'{source.name}:{size}:{stamp}'
    key = 'library-preview-v1:' + hashlib.sha256(fingerprint.encode()).hexdigest()
    found = cache.get(key)
    if found is not None:
        return found or None
    if not _render_slots.acquire(timeout=3):
        return None
    try:
        if extension in _video_extensions:
            result = _video_preview(source)
        elif extension == '.pdf':
            import pypdfium2 as pdfium
            with source.open('rb') as file:
                contents = file.read()
            with _pdf_lock, pdfium.PdfDocument(contents) as document:
                if not len(document):
                    return None
                with closing(document[0]) as page:
                    width, height = page.get_size()
                    if width <= 0 or height <= 0:
                        return None
                    bitmap = page.render(scale=min(480 / width, 640 / height, 2))
                    try:
                        result = _jpeg(bitmap.to_pil())
                    finally:
                        bitmap.close()
        elif extension in {'.png', '.jpg', '.jpeg', '.webp', '.gif'}:
            with source.open('rb') as file, Image.open(file) as image:
                result = _jpeg(image)
        else:
            result = None
        cache.set(key, result or b'', 3600 if result else 60)
        return result
    except Exception:
        # A broken/unsupported preview must never prevent browsing the output.
        logger.debug('Repository preview unavailable for %s', source.name, exc_info=True)
        cache.set(key, b'', 60)
        return None
    finally:
        _render_slots.release()

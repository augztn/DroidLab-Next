"""Safe payload-dumper-go adapter based on the audited legacy implementation."""
from __future__ import annotations
import hashlib, os, shutil, subprocess, sys, tempfile
from pathlib import Path
from .command_guards import is_valid_partition_name
from .tool_resolver import resolve_tool_path
from .process_runner import run_streaming, ProcessCancelledError
from .file_transfer import publish_file_no_replace
class BackendError(RuntimeError): pass
INSPECTION_TIMEOUT=120
EXTRACTION_TIMEOUT=3600
def _find_cli():
 # Resolve env, shared config, platform bundle, then PATH in one place.
 bundle_root = Path(__file__).resolve().parents[3].parent
 try:
  return [resolve_tool_path("payload-dumper-go", bundle_root=bundle_root)]
 except RuntimeError as exc:
  raise BackendError(str(exc)) from exc
def _run(cli,args,progress=None,cancel_event=None,timeout=INSPECTION_TIMEOUT):
 try:return run_streaming(cli+args,timeout=timeout,cancel_event=cancel_event,on_line=progress)
 except ProcessCancelledError as exc: raise BackendError("Payload operation cancelled.") from exc
 except subprocess.TimeoutExpired as exc: raise BackendError(f"Payload operation timed out after {exc.timeout} seconds.") from exc
 except OSError as exc: raise BackendError(f"Could not start payload-dumper-go: {exc}") from exc
def _parse_partition_list(output):
    """Parse payload-dumper-go -l -m output (name:size_in_KiB)."""
    parts = []
    seen = set()
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line or ":" not in line:
            continue
        name, raw_size = line.rsplit(":", 1)
        name = name.strip()
        if not is_valid_partition_name(name) or name.casefold() in seen:
            continue
        try:
            size_kib = int(raw_size.strip())
        except ValueError:
            continue
        if size_kib < 0:
            continue
        seen.add(name.casefold())
        parts.append({"name": name, "size_bytes": size_kib * 1024})
    return parts


def inspect_source(source, progress=None, cancel_event=None):
    if not isinstance(source, str) or not source.strip():
        raise BackendError("Choose an OTA ZIP or payload.bin file.")
    path = Path(source).expanduser()
    if not path.is_file():
        raise BackendError(f"Input file does not exist: {path}")
    if path.suffix.lower() not in {".bin", ".zip"}:
        raise BackendError("Choose a payload .bin file or OTA .zip file.")
    cli = _find_cli()
    result = _run(
        cli,
        ["-l", "-m", str(path.resolve())],
        progress,
        cancel_event,
        INSPECTION_TIMEOUT,
    )
    if result.returncode:
        detail = result.stdout.strip() or "payload-dumper-go returned a non-zero exit status."
        raise BackendError(detail)
    parts = _parse_partition_list(result.stdout)
    if not parts:
        detail = result.stdout.strip()
        if detail:
            raise BackendError(
                "Could not parse the partition list returned by payload-dumper-go. "
                "Expected machine-readable lines in name:size_in_KiB format. "
                f"Tool output: {detail[:1200]}"
            )
        raise BackendError(
            "payload-dumper-go returned no partition metadata. "
            "Verify that the input is a full OTA ZIP or payload.bin."
        )
    return parts
def extract(source,output_dir,selected=None,progress=None,cancel_event=None,fingerprint=False):
 if not isinstance(source,str) or not source.strip():raise BackendError("Choose a payload .bin or OTA .zip file.")
 if not isinstance(output_dir,str) or not output_dir.strip():raise BackendError("Choose an output directory.")
 src=Path(source).expanduser().resolve(); out=Path(output_dir).expanduser().resolve()
 if not src.is_file() or src.suffix.lower() not in {".bin",".zip"}:raise BackendError("Choose an existing payload .bin or OTA .zip file.")
 if selected and any(not is_valid_partition_name(p) for p in selected):raise BackendError("Invalid partition selection.")
 cli=_find_cli()
 if not cli:raise BackendError("payload-dumper-go was not found.")
 out.mkdir(parents=True,exist_ok=True); stage=Path(tempfile.mkdtemp(prefix=".droidlab-stage-",dir=out.parent)); published=[]
 try:
  args=["-o",str(stage)]
  if selected:args.extend(["-p",",".join(selected)])
  args.append(str(src)); result=_run(cli,args,progress,cancel_event,EXTRACTION_TIMEOUT)
  if result.returncode:raise BackendError(f"payload-dumper-go exited with status {result.returncode}; delta OTA operations may be unsupported.")
  if cancel_event is not None and cancel_event.is_set():raise BackendError("Extraction cancelled before artifact publication.")
  artifacts=sorted(p for p in stage.rglob("*.img") if p.is_file() and not p.is_symlink() and p.stat().st_size>0)
  if not artifacts:raise BackendError("Extraction produced no non-empty image artifacts.")
  if selected and not {x.casefold() for x in selected}.issubset({p.stem.casefold() for p in artifacts}):raise BackendError("Extraction did not produce every requested partition image.")
  root=out.resolve()
  for artifact in artifacts:
   if cancel_event is not None and cancel_event.is_set():raise BackendError("Extraction cancelled during artifact publication.")
   dest=out/artifact.relative_to(stage); dest.parent.mkdir(parents=True,exist_ok=True)
   if not dest.parent.resolve().is_relative_to(root):raise BackendError("Artifact resolves outside output directory.")
   if dest.exists() or dest.is_symlink():raise BackendError(f"Output already exists and will not be overwritten: {dest}")
   publish_file_no_replace(artifact,dest); published.append(dest); artifact.unlink()
  results=[]
  for path in published:
   item={"path":str(path),"name":path.name,"size_bytes":path.stat().st_size}
   if fingerprint:
    try:item["sha256"]=sha256_file(path)
    except OSError as exc:item["fingerprint_warning"]=str(exc)
   results.append(item)
  return results
 except Exception:
  for path in reversed(published):
   try:path.unlink(missing_ok=True)
   except OSError:pass
  raise
 finally:shutil.rmtree(stage,ignore_errors=True)
def sha256_file(path,chunk_size=1024*1024):
 digest=hashlib.sha256()
 with open(path,"rb") as f:
  for chunk in iter(lambda:f.read(chunk_size),b""):digest.update(chunk)
 return digest.hexdigest()

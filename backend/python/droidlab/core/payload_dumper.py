"""Safe payload-dumper-go adapter based on the audited legacy implementation."""
from __future__ import annotations
import hashlib, os, shutil, subprocess, sys, tempfile
from pathlib import Path
from .command_guards import is_valid_partition_name
from .process_runner import run_streaming, ProcessCancelledError
class BackendError(RuntimeError): pass
INSPECTION_TIMEOUT=120
EXTRACTION_TIMEOUT=3600
def _find_cli():
 root=Path(__file__).resolve().parents[3]
 candidates=[root/"bin"/"payload-dumper-go",root/"opt"/"payload-dumper"/"bin"/"payload-dumper-go",Path(sys.executable).resolve().parent/"payload-dumper-go"]
 for path in candidates:
  if path.is_file() and (os.name=="nt" or os.access(path,os.X_OK)): return [str(path)]
 for name in ("payload-dumper-go","payload-dumper-go.exe"):
  found=shutil.which(name)
  if found:return [found]
 return None
def _run(cli,args,progress=None,cancel_event=None,timeout=INSPECTION_TIMEOUT):
 try:return run_streaming(cli+args,timeout=timeout,cancel_event=cancel_event,on_line=progress)
 except ProcessCancelledError as exc: raise BackendError("Payload operation cancelled.") from exc
 except subprocess.TimeoutExpired as exc: raise BackendError(f"Payload operation timed out after {exc.timeout} seconds.") from exc
 except OSError as exc: raise BackendError(f"Could not start payload-dumper-go: {exc}") from exc
def inspect_source(source,progress=None,cancel_event=None):
 path=Path(source).expanduser().resolve()
 if not path.is_file():raise BackendError(f"Input file does not exist: {path}")
 cli=_find_cli()
 if not cli:raise BackendError("payload-dumper-go was not found. Install it or use the bundled AppImage.")
 result=_run(cli,["-l","-m",str(path)],progress,cancel_event,INSPECTION_TIMEOUT)
 if result.returncode:raise BackendError(result.stdout.strip() or "Could not inspect OTA payload.")
 parts=[]
 for line in result.stdout.splitlines():
  name,sep,size=line.partition(":")
  if not sep:continue
  try: size_bytes=int(size.strip())*1024
  except ValueError:continue
  if is_valid_partition_name(name.strip()):parts.append({"name":name.strip(),"size_bytes":size_bytes})
 if not parts:raise BackendError("Payload backend returned no valid partition metadata.")
 return parts
def extract(source,output_dir,selected=None,progress=None,cancel_event=None,fingerprint=False):
 src=Path(source).expanduser().resolve(); out=Path(output_dir).expanduser().resolve()
 if not src.is_file() or src.suffix.lower() not in {".bin",".zip"}:raise BackendError("Choose an existing payload .bin or OTA .zip file.")
 if not output_dir.strip():raise BackendError("Choose an output directory.")
 if selected and any(not is_valid_partition_name(p) for p in selected):raise BackendError("Invalid partition selection.")
 cli=_find_cli()
 if not cli:raise BackendError("payload-dumper-go was not found.")
 out.mkdir(parents=True,exist_ok=True); stage=Path(tempfile.mkdtemp(prefix=".droidlab-stage-",dir=out.parent)); published=[]
 try:
  args=["-o",str(stage)]
  if selected:args.extend(["-p",",".join(selected)])
  args.append(str(src)); result=_run(cli,args,progress,cancel_event,EXTRACTION_TIMEOUT)
  if result.returncode:raise BackendError(f"payload-dumper-go exited with status {result.returncode}; delta OTA operations may be unsupported.")
  artifacts=sorted(p for p in stage.rglob("*.img") if p.is_file() and not p.is_symlink() and p.stat().st_size>0)
  if not artifacts:raise BackendError("Extraction produced no non-empty image artifacts.")
  if selected and {p.stem.casefold() for p in artifacts} < {x.casefold() for x in selected}:raise BackendError("Extraction did not produce every requested partition image.")
  root=out.resolve()
  for artifact in artifacts:
   dest=out/artifact.relative_to(stage); dest.parent.mkdir(parents=True,exist_ok=True)
   if not dest.parent.resolve().is_relative_to(root):raise BackendError("Artifact resolves outside output directory.")
   if dest.exists() or dest.is_symlink():raise BackendError(f"Output already exists and will not be overwritten: {dest}")
   os.link(artifact,dest); published.append(dest); artifact.unlink()
  results=[]
  for path in published:
   item={"path":str(path),"name":path.name,"size_bytes":path.stat().st_size}
   if fingerprint:item["sha256"]=sha256_file(path)
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

"""Bounded subprocess execution with cancellation and output streaming."""
from __future__ import annotations
import math, os, queue, signal, subprocess, threading, time
from collections.abc import Callable, Sequence
class ProcessCancelledError(RuntimeError): pass
def terminate_process(proc,grace_seconds=1.0):
 if not math.isfinite(grace_seconds) or grace_seconds<0: raise ValueError("grace_seconds must be finite and non-negative")
 if os.name=="nt":
  try: subprocess.run(["taskkill","/PID",str(proc.pid),"/T","/F"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=max(1.0,grace_seconds+1),check=False)
  except (OSError,subprocess.TimeoutExpired): pass
  if proc.poll() is None:
   try: proc.terminate(); proc.wait(timeout=grace_seconds)
   except subprocess.TimeoutExpired:
    proc.kill()
    try: proc.wait(timeout=grace_seconds)
    except subprocess.TimeoutExpired: pass
   except OSError: pass
  return
 try: os.killpg(proc.pid,signal.SIGTERM)
 except (ProcessLookupError,PermissionError,OSError):
  if proc.poll() is None:
   try: proc.terminate()
   except OSError: pass
 try: proc.wait(timeout=grace_seconds)
 except subprocess.TimeoutExpired: pass
 try: os.killpg(proc.pid,signal.SIGKILL)
 except (ProcessLookupError,PermissionError,OSError):
  if proc.poll() is None:
   try: proc.kill()
   except OSError: pass
 try: proc.wait(timeout=grace_seconds)
 except subprocess.TimeoutExpired: pass
def run_streaming(command:Sequence[str],*,timeout:float|None=None,cancel_event:threading.Event|None=None,on_line:Callable[[str],None]|None=None,max_output_chars=2*1024*1024,max_queue_lines=1000):
 if not command or any(not isinstance(a,str) or "\x00" in a for a in command): raise ValueError("command must be a non-empty string argument list without NUL bytes")
 if max_output_chars < 1 or max_queue_lines < 1: raise ValueError("output and queue bounds must be positive")
 if timeout is not None and (not math.isfinite(timeout) or timeout<0): raise ValueError("timeout must be finite and non-negative")
 if cancel_event and cancel_event.is_set(): raise ProcessCancelledError("Cancelled before launch")
 kwargs={"start_new_session":True} if os.name=="posix" else {}
 proc=subprocess.Popen(list(command),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,text=True,encoding="utf-8",errors="replace",bufsize=1,**kwargs)
 stream=proc.stdout; lines=queue.Queue(maxsize=max_queue_lines); dropped=[0]
 def reader():
  try:
   while True:
    line=stream.readline(16*1024)
    if not line:break
    try: lines.put_nowait(line)
    except queue.Full: dropped[0]+=1
  finally:
   while True:
    try: lines.put_nowait(None); break
    except queue.Full:
     try: lines.get_nowait(); dropped[0]+=1
     except queue.Empty: pass
 thread=threading.Thread(target=reader,daemon=True); thread.start(); deadline=None if timeout is None else time.monotonic()+timeout
 output=[]; size=0; omitted=0
 try:
  while True:
   if cancel_event and cancel_event.is_set(): raise ProcessCancelledError("Cancelled by user")
   if deadline is not None and time.monotonic()>=deadline: raise subprocess.TimeoutExpired(list(command),timeout)
   try: line=lines.get(timeout=.1)
   except queue.Empty: continue
   if line is None: break
   if on_line: on_line(line.rstrip("\r\n"))
   if size+len(line)<=max_output_chars: output.append(line); size+=len(line)
   else: omitted+=1
  code=proc.wait(timeout=2); omitted+=dropped[0]
  if omitted: output.append(f"\n[DroidLab: {omitted} output line(s) omitted]\n")
  return subprocess.CompletedProcess(list(command),code,"".join(output),"")
 except BaseException:
  terminate_process(proc); raise
 finally:
  try: stream.close()
  except (OSError,ValueError): pass
  thread.join(timeout=.2)

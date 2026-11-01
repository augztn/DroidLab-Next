"""Pure command safety checks shared by the UI and protocol backend."""
from __future__ import annotations
import re
from pathlib import PurePath

_ADB_DESTRUCTIVE_VERBS = {"reboot","sideload","root","unroot","remount","disable-verity","enable-verity","uninstall","erase","format","flash","wipe"}
_SHELL_DESTRUCTIVE_PATTERNS = (
 re.compile(r"(?:^|[;&|]\s*)rm\s+(?:-[a-z]*r[a-z]*f\b|-[a-z]*r\s+-[a-z]*f\b|-[a-z]*f\s+-[a-z]*r\b)", re.I),
 re.compile(r"(?:^|[;&|]\s*)(?:mkfs(?:\.[\w-]+)?|dd|reboot|poweroff|shutdown|wipe|format)\b", re.I),
 re.compile(r"(?:^|[;&|]\s*)setprop\b", re.I),
 re.compile(r"(?:^|[;&|]\s*)pm\s+(?:uninstall|disable-user)\b", re.I),
 re.compile(r"(?:^|[;&|]\s*)svc\b[^;&|]*\bdisable\b", re.I),
)
_FASTBOOT_DESTRUCTIVE_VERBS = {"flash","flashall","erase","format","wipe","set_active","update","delete-logical-partition","create-logical-partition","resize-logical-partition"}
def _strip_executable(tokens,names):
 values=list(tokens)
 if values and PurePath(values[0].strip('"')).name.lower() in names: values.pop(0)
 return values
def _skip_device_options(tokens):
 values,index=list(tokens),0; takes={"-s","-t","-H","-P","-L","-i","-p","-c"}
 while index<len(values):
  token=values[index].lower()
  if token in takes and index+1<len(values): index+=2
  elif token in {"-d","-e"}: index+=1
  else: break
 return values[index:]
def _is_destructive_shell_text(text,depth=0):
 text=text.strip()
 if not text: return False
 if any(pattern.search(text) for pattern in _SHELL_DESTRUCTIVE_PATTERNS): return True
 if depth>=4: return False
 wrapper=re.search(r"(?:^|[;&|]\s*)(?:(?:/[^\s;&|]+/)?(?:sh|bash|ash|dash|mksh|ksh|zsh)|su)\s+(?:-[a-z]*c\s+|--command(?:=|\s+))(.+)$",text,re.I)
 if wrapper:
  nested=wrapper.group(1).strip()
  if len(nested)>=2 and nested[0]==nested[-1] and nested[0] in {"'",'"'}: nested=nested[1:-1]
  return _is_destructive_shell_text(nested,depth+1)
 return False
def is_destructive_adb(tokens):
 values=_skip_device_options(_strip_executable(list(tokens),{"adb","adb.exe"}))
 if not values:return False
 verb=values[0].lower()
 return verb in _ADB_DESTRUCTIVE_VERBS or (verb=="shell" and _is_destructive_shell_text(" ".join(values[1:])))
def is_destructive_fastboot(tokens):
 values=_strip_executable(list(tokens),{"fastboot","fastboot.exe"})
 if any(token.lower()=="-w" for token in values):return True
 values=_skip_device_options(values); lowered=[token.lower() for token in values]
 if not lowered:return False
 verb=lowered[0]
 if verb in _FASTBOOT_DESTRUCTIVE_VERBS:return True
 if verb=="oem" and len(lowered)>1 and lowered[1]=="unlock":return True
 return verb=="flashing" and len(lowered)>1 and lowered[1] in {"unlock","unlock_critical","lock","lock_critical"}
def is_valid_partition_name(name):return isinstance(name,str) and bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*",name))
def explicit_device_selector(tokens,tool):
 values=list(tokens)
 if values and PurePath(values[0].strip('"')).name.lower() in {"adb","adb.exe","fastboot","fastboot.exe"}:values.pop(0)
 tool=tool.lower()
 if tool not in {"adb","fastboot"}:raise ValueError("tool must be 'adb' or 'fastboot'")
 selector=None;index=0
 takes={"-s"}|({"-t","-H","-P","-L"} if tool=="adb" else {"-i","-p","-c","--slot"})
 no_value={"-d","-e"} if tool=="adb" else {"-w","-l","--set-active"}
 while index<len(values):
  token=values[index]
  if token=="--":break
  if token.startswith("-s="):
   candidate=token[3:]
   if not candidate:raise ValueError("Missing serial after -s")
   index+=1
  elif token=="-s":
   if index+1>=len(values) or not values[index+1] or values[index+1].startswith("-"):raise ValueError("Missing serial after -s")
   candidate=values[index+1];index+=2
  elif token in takes:
   if index+1>=len(values) or not values[index+1]:raise ValueError(f"Missing value after {token}")
   index+=2;continue
  elif token in no_value:index+=1;continue
  elif token.startswith("-"):break
  else:break
  if selector is not None:raise ValueError("Repeated device serial selector is ambiguous")
  selector=candidate
 return selector
def validate_device_selector(tokens,tool,selected_serial):
 explicit=explicit_device_selector(tokens,tool)
 if explicit is not None and selected_serial and explicit!=selected_serial:raise ValueError(f"Command targets serial {explicit!r}, but selected device is {selected_serial!r}.")
 if explicit is not None and not selected_serial:raise ValueError(f"Command explicitly targets {explicit!r}, but no matching device is selected.")
 return explicit
def is_adb_target_connected(serial,output,returncode=0,allowed_states=("device",)):
 if returncode!=0 or not serial:return False
 for line in output.splitlines():
  fields=line.split()
  if len(fields)>=2 and fields[0]==serial and fields[1] in allowed_states:return True
 return False
def is_fastboot_target_connected(serial,output,returncode=0):
 if returncode!=0 or not serial:return False
 return any(len(fields:=line.split())>=2 and fields[0]==serial and fields[1].lower() in {"fastboot", "fastbootd"} for line in output.splitlines())

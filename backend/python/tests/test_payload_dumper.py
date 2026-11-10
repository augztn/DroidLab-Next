import hashlib, os, sys, tempfile, unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from droidlab.core import payload_dumper

class PayloadDumperTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
  self.source=self.root/"ota.zip";self.source.write_bytes(b"fixture")
  self.binary=self.root/"payload-dumper-go"
  self.binary.write_text("#!/usr/bin/env python3\nimport pathlib,sys\na=sys.argv[1:]\nif '-l' in a:\n print('boot:4')\n print('system:8')\nelse:\n out=pathlib.Path(a[a.index('-o')+1]);(out/'boot.img').write_bytes(b'hello')\n",encoding="utf-8")
  self.binary.chmod(0o755);self.env=patch.dict(os.environ,{"DROIDLAB_PAYLOAD_DUMPER_GO_PATH":str(self.binary)});self.env.start()
 def tearDown(self):self.env.stop();self.temp.cleanup()
 def test_machine_readable_partition_listing_parses_kib_sizes(self):
  output = "boot:4\nsystem:8\n"
  self.assertEqual(
   payload_dumper._parse_partition_list(output),
   [{"name":"boot","size_bytes":4096},{"name":"system","size_bytes":8192}],
  )
 def test_partition_parser_ignores_headers_and_duplicate_names(self):
  output = "payload.bin: ota.zip\nPayload Version: 2\nboot:4\nboot:8\n"
  self.assertEqual(payload_dumper._parse_partition_list(output),[{"name":"boot","size_bytes":4096}])
 def test_partition_parser_rejects_invalid_sizes_and_names(self):
  self.assertEqual(payload_dumper._parse_partition_list("boot:nope\n../system:4\nmetadata:-1\n"),[])
 def test_inspection_parses_partition_metadata(self):
  self.assertEqual(payload_dumper.inspect_source(str(self.source)),[{"name":"boot","size_bytes":4096},{"name":"system","size_bytes":8192}])
 def test_extract_publishes_image_and_sha256(self):
  output=self.root/"images";result=payload_dumper.extract(str(self.source),str(output),["boot"],fingerprint=True)
  self.assertEqual((output/"boot.img").read_bytes(),b"hello");self.assertEqual(result[0]["sha256"],hashlib.sha256(b"hello").hexdigest())
 def test_existing_file_is_not_overwritten(self):
  output=self.root/"images";output.mkdir();dest=output/"boot.img";dest.write_bytes(b"keep")
  with self.assertRaises(payload_dumper.BackendError):payload_dumper.extract(str(self.source),str(output),["boot"])
  self.assertEqual(dest.read_bytes(),b"keep")
 def test_extract_falls_back_when_output_filesystem_rejects_hard_links(self):
  output=self.root/"images"
  with patch("droidlab.core.file_transfer.os.link",side_effect=OSError(__import__("errno").EOPNOTSUPP,"unsupported")):
   result=payload_dumper.extract(str(self.source),str(output),["boot"])
  self.assertEqual((output/"boot.img").read_bytes(),b"hello")
  self.assertEqual(result[0]["size_bytes"],5)
  self.assertEqual(list(self.root.glob(".droidlab-stage-*")),[])

 def test_invalid_partition_is_rejected(self):
  with self.assertRaises(payload_dumper.BackendError):payload_dumper.extract(str(self.source),str(self.root/"images"),["../userdata"])

 def test_payload_dumper_uses_shared_settings_path(self):
  configured=self.root/ "configured-payload-dumper"
  configured.write_text("binary",encoding="utf-8");configured.chmod(0o755)
  home=self.root/"home";config=home/"DroidLab"/"config.json";config.parent.mkdir(parents=True)
  config.write_text('{"payload_dumper_path":'+__import__("json").dumps(str(configured))+'}',encoding="utf-8")
  with patch.dict(os.environ,{"HOME":str(home),"DROIDLAB_PAYLOAD_DUMPER_GO_PATH":""}):
   self.assertEqual(payload_dumper._find_cli(),[str(configured.resolve())])

 def test_finds_payload_dumper_next_to_desktop_bundle(self):
  bundle=self.root/"bundle"; backend=bundle/"backend/python/droidlab/core"; backend.mkdir(parents=True)
  binary=bundle/"payload-dumper-go"; binary.write_text("binary",encoding="utf-8"); binary.chmod(0o755)
  with patch.dict(os.environ,{},clear=True), patch.object(payload_dumper,"__file__",str(backend/"payload_dumper.py")), patch.object(payload_dumper.shutil,"which",return_value=None):
   self.assertEqual(payload_dumper._find_cli(),[str(binary)])
if __name__=="__main__":unittest.main()

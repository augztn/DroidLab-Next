import sys,threading,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from droidlab.core.process_runner import run_streaming,ProcessCancelledError
class ProcessRunnerTests(unittest.TestCase):
 def test_capture_output(self):
  result=run_streaming([sys.executable,"-c","print('ready')"],timeout=5)
  self.assertEqual(result.returncode,0);self.assertIn("ready",result.stdout)
 def test_cancel_before_launch(self):
  event=threading.Event();event.set()
  with self.assertRaises(ProcessCancelledError):run_streaming([sys.executable,"-c","print('no')"],cancel_event=event)
if __name__=="__main__":unittest.main()

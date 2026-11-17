# Evaluation-only local ONNX transport; never imported by the application.
# SPDX-License-Identifier: MIT
import sys,json,hashlib,base64
from pathlib import Path
import numpy as np
import onnxruntime as ort
model=Path(sys.argv[1]);h=hashlib.sha256()
with model.open('rb') as f:
 for chunk in iter(lambda:f.read(1048576),b''):h.update(chunk)
options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1;options.execution_mode=ort.ExecutionMode.ORT_SEQUENTIAL;options.enable_cpu_mem_arena=False;options.enable_mem_pattern=False
session=ort.InferenceSession(str(model),sess_options=options,providers=['CPUExecutionProvider'])
print(json.dumps({'ready':True,'sha256':h.hexdigest(),'outputs':[o.name for o in session.get_outputs()]}),flush=True)
for line in sys.stdin:
 try:
  request=json.loads(line);ids=np.asarray([request['ids']],dtype=np.int64);mask=np.asarray([request['mask']],dtype=np.int64)
  if ids.shape!=mask.shape or ids.shape[1]>512 or not np.all(mask==1):raise ValueError('Invalid prepared input')
  outputs=session.run(['logits_labels','logits_d'],{'input_ids':ids,'attention_mask':mask})
  result={'labels':base64.b64encode(np.asarray(outputs[0],dtype='<f4').tobytes()).decode(),'detection':base64.b64encode(np.asarray(outputs[1],dtype='<f4').tobytes()).decode()}
  print(json.dumps(result),flush=True)
 except Exception as exc:print(json.dumps({'error':str(exc)}),flush=True)

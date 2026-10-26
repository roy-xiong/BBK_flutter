"""沿用用户确认的本机MFLUX流程，串行生成可追溯原稿，限制大图的Metal占用。"""
from pathlib import Path
import argparse,json,os,subprocess,sys,time,hashlib
from PIL import Image


def main():
 p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--cache',type=Path,required=True);p.add_argument('--only',nargs='*');p.add_argument('--plan',type=Path);args=p.parse_args()
 if args.plan:args.only=json.loads(args.plan.read_text())
 env=dict(os.environ,HF_HOME=str(args.cache),HF_HUB_DISABLE_IMPLICIT_TOKEN='1',HF_HUB_DISABLE_TELEMETRY='1',HF_HUB_DISABLE_PROGRESS_BARS='1',HF_HUB_OFFLINE='1',PYTHONUNBUFFERED='1')
 for job in json.loads((args.root/'requests.json').read_text()):
  if args.only and job['id'] not in args.only:continue
  output=args.root/'generated'/(job['id']+'.png')
  if output.exists():
   with Image.open(output) as im:im.verify()
   print('SKIP',job['id'],flush=True);continue
  # 同机另一游戏也在生成素材时，等其当前单项完成；不终止或修改其他任务。
  wait_started=time.monotonic();last_notice=-10
  while True:
   processes=subprocess.run(['ps','-axo','pid=,args='],capture_output=True,text=True).stdout
   import shlex
   active=[]
   for line in processes.splitlines():
    try:parts=shlex.split(line)
    except ValueError:continue
    if parts and int(parts[0])!=os.getpid() and any(Path(token).name.startswith('mflux-generate-') for token in parts[1:3]):active.append(parts)
   if not active:break
   # 实测512×640单图峰值3.41GB。只允许与一个不超过此大小的小图共存，
   # 大图仍独占，避免同机另一长队列持续占用时本队列无限饥饿。
   small=job['width']*job['height']<=512*640
   for other in active:
    try:small=small and int(other[other.index('--width')+1])*int(other[other.index('--height')+1])<=512*640
    except (ValueError,IndexError):small=False
   if len(active)==1 and small:break
   elapsed=time.monotonic()-wait_started
   if elapsed-last_notice>=15:
    print('WAIT Metal image generation is in use',flush=True);last_notice=elapsed
   # 较短检查间隔用于接上当前图片结束后的空档，避免另一串行队列让本队列一直饥饿。
   time.sleep(.035)
  prompt=output.with_suffix('.prompt.txt');prompt.write_text(job['prompt'])
  cli=Path(sys.executable).parent/('mflux-generate-flux2-edit' if job['refs'] else 'mflux-generate-flux2')
  command=[str(cli),'--model','mlx-community/flux2-klein-4b-4bit','--base-model','flux2-klein-4b','--quantize','4','--low-ram']
  if job['refs']:command+=['--image-paths',*[str(args.root/r) for r in job['refs']]]
  command+=['--prompt-file',str(prompt),'--width',str(job['width']),'--height',str(job['height']),'--steps','4','--guidance','1','--seed',str(job['seed']),'--make-conf','--output',str(output)]
  print('START',job['id'],flush=True);started=time.monotonic()
  with output.with_suffix('.log').open('w') as log:result=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT)
  if result.returncode!=0 or not output.exists():
   print('FAILED',job['id'],'see',output.with_suffix('.log'),flush=True);raise SystemExit(1)
  with Image.open(output) as im:im.verify()
  record=dict(job,model='mlx-community/flux2-klein-4b-4bit',mflux='0.23.0',steps=4,seconds=round(time.monotonic()-started,2),sha256=hashlib.sha256(output.read_bytes()).hexdigest())
  output.with_suffix('.provenance.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n');print('DONE',job['id'],record['seconds'],flush=True)

if __name__=='__main__':main()

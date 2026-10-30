"""将真实录制的GIF无损转为动画WebP，逐帧比对解码像素和时长，不重新绘制。"""
from pathlib import Path
import argparse,json
from PIL import Image

def main():
    p=argparse.ArgumentParser();p.add_argument('--input',type=Path,default=Path('build/battle-review'));a=p.parse_args()
    for metadata in a.input.glob('shard-*.json'):
        records=json.loads(metadata.read_text())
        for i,c in enumerate(records):
            src=a.input/(c['id']+'.gif');out=src.with_suffix('.webp')
            if not src.exists()and out.exists():
                # 新版录制已直接输出无损WebP，保持原文件，不再经过GIF调色板。
                with Image.open(out)as animation:
                    total=0
                    for frame in range(animation.n_frames):animation.seek(frame);animation.load();total+=animation.info.get('duration',0)
                    assert total==c['durationMs']+c['loopGapMs'],c['id']
                    c.update(webpFrames=animation.n_frames,webpDurationMs=total,webpBytes=out.stat().st_size)
                continue
            with Image.open(src)as gif:
                frames=[];durations=[]
                for index in range(gif.n_frames):
                    gif.seek(index);frames.append(gif.convert('RGBA'));durations.append(gif.info.get('duration',0))
            frames[0].save(out,format='WEBP',save_all=True,append_images=frames[1:],duration=durations,loop=0,lossless=True,method=4,minimize_size=True,exact=True)
            with Image.open(out)as image:
                assert image.n_frames==len(frames),(c['id'],image.n_frames,len(frames))
                total=0
                for index,original in enumerate(frames):
                    image.seek(index);image.load();total+=image.info.get('duration',0)
                    assert image.convert('RGBA').tobytes()==original.tobytes(),(c['id'],index,'pixels changed')
                assert total==sum(durations),(c['id'],total,sum(durations))
            c.update(webpFrames=len(frames),webpDurationMs=total,webpBytes=out.stat().st_size)
            for f in frames:f.close()
            if(i+1)%20==0:print(metadata.stem,i+1,flush=True)
        metadata.write_text(json.dumps(records,ensure_ascii=False,separators=(',',':')))
        print('compacted',metadata.name,'gifMiB',sum(c['gifBytes']for c in records)/1048576,'webpMiB',sum(c['webpBytes']for c in records)/1048576,flush=True)
if __name__=='__main__':main()

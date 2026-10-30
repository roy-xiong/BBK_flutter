"""将40ms真实战斗帧编码为动图（直接无损WebP或兼容GIF），保留每帧时长和600ms循环间隔。"""
from pathlib import Path
import argparse,json
from PIL import Image

def main():
    p=argparse.ArgumentParser();p.add_argument('input',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
    timeline=json.loads((a.input/'timeline.json').read_text())
    frames=[Image.open(a.input/r['file']).convert('RGB')for r in timeline]
    durations=[r['ms']for r in timeline]
    if a.output.suffix.lower()=='.webp'and len(frames)==1:
        # 黑白的虚弱/倒地等案例可能整段完全静止。单帧WebP不存动画时长，
        # 改用带GCE时长的单帧GIF，不能篡改像素或伪造第二帧来凑动画。
        out=a.output.with_suffix('.gif')
        frames[0].save(out,format='GIF',duration=sum(durations),loop=0)
        with Image.open(out)as image:
            image.load()
            assert image.info['duration']==sum(durations)
            assert image.convert('RGB').tobytes()==frames[0].tobytes()
        print(json.dumps({'frames':1,'durationMs':sum(durations),'bytes':out.stat().st_size,'extension':'gif'}))
        return
    if a.output.suffix.lower()=='.webp':
        # 直接从正式PNG帧编码，避免先转GIF的256色限制损失细化动效的渐变细节。
        frames[0].save(a.output,format='WEBP',save_all=True,append_images=frames[1:],duration=durations,loop=0,lossless=True,method=4,minimize_size=True,exact=True)
        with Image.open(a.output)as animation:
            assert animation.n_frames==len(frames)
            total=0
            for i,original in enumerate(frames):
                animation.seek(i);animation.load();total+=animation.info.get('duration',0)
                assert animation.convert('RGB').tobytes()==original.tobytes(),(i,'render pixels changed')
            assert total==sum(durations)
            print(json.dumps({'frames':animation.n_frames,'durationMs':total,'bytes':a.output.stat().st_size,'extension':'webp'}))
        return
    # 从全过程取样，既包含背景/角色，也包含后来出现的技能色彩。
    samples=frames[::max(1,len(frames)//24)][:24]
    sheet=Image.new('RGB',(160*len(samples),96))
    for i,im in enumerate(samples):sheet.paste(im.resize((160,96),Image.Resampling.BILINEAR),(160*i,0))
    palette=sheet.quantize(colors=256,method=Image.Quantize.MEDIANCUT)
    converted=[im.quantize(palette=palette,dither=Image.Dither.NONE)for im in frames]
    durations=[r['ms']for r in timeline]
    converted[0].save(a.output,save_all=True,append_images=converted[1:],duration=durations,loop=0,optimize=True,disposal=1)
    with Image.open(a.output)as gif:
        total=0
        for i in range(gif.n_frames):gif.seek(i);total+=gif.info.get('duration',0)
        assert total==sum(durations),(total,sum(durations))
        result={'frames':gif.n_frames,'durationMs':total,'bytes':a.output.stat().st_size}
    print(json.dumps(result))
if __name__=='__main__':main()

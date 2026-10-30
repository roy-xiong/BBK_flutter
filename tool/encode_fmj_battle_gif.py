"""将40ms真实战斗帧编码为统一调色板GIF，保留每帧时长和600ms循环间隔。"""
from pathlib import Path
import argparse,json
from PIL import Image

def main():
    p=argparse.ArgumentParser();p.add_argument('input',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
    timeline=json.loads((a.input/'timeline.json').read_text())
    frames=[Image.open(a.input/r['file']).convert('RGB')for r in timeline]
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

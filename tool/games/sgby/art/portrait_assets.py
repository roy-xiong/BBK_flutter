"""正式头像：经核对的1994年角色剧照；缺图时逐人物ID回退原始黑白像素。"""
from pathlib import Path
import hashlib
import json
import re
import struct
from PIL import Image,ImageOps

ROOT=Path(__file__).resolve().parents[2]
CORRECTIONS=dict(re.findall("'([^']+)': '([^']+)'",(ROOT/'lib/engine/resources/person_names.dart').read_text()))


def corrected(name):
    return CORRECTIONS.get(name,name)


class OriginalArchive:
    """只读美术导出器，保持与Dart资源层相同的条目号和减密钥规则。"""
    def __init__(self):
        self.raw=(ROOT/'assets/game/SGBY-Reset-4X.lib').read_bytes()
    def item(self,resource,index=1):
        offset=struct.unpack_from('<I',self.raw,(resource-1)*4)[0]
        _,_,count,length,key=struct.unpack_from('<IHHIB',self.raw,offset)
        if index<1 or index>max(1,count):return b''
        start,size=(14+(index-1)*length,length) if length else struct.unpack_from('<II',self.raw,offset+14+(index-1)*8)
        return bytes((v-key)&255 for v in self.raw[offset+start:offset+start+size])
    def head(self,period,index):
        raw=self.item(47+period);w,h,count,flags=struct.unpack_from('<HHHB',raw)
        if index<0 or index>=count:raise ValueError('Original portrait missing: '+str((period,index)))
        stride=(w+7)//8;plane=stride*h;offset=7+index*plane*(2 if flags&1 else 1)
        mask=raw[offset:offset+plane] if flags&1 else None
        data=raw[offset+(plane if mask else 0):offset+plane*(2 if mask else 1)]
        image=Image.new('RGBA',(w,h),(180,180,180,255));pixels=image.load()
        for y in range(h):
            for x in range(w):
                position=y*stride+x//8;bit=1<<(7-x%8)
                if data[position]&bit:pixels[x,y]=(0,0,0,255)
                elif mask and mask[position]&bit:pixels[x,y]=(180,180,180,0)
        return image


def build_portraits():
    """照片绑定按纠正姓名，原头像绑定按时期/编号，绝不借用别人的脸补位。"""
    registry=json.loads((ROOT/'tool/art/portraits_1994.json').read_text())
    approved={p['name']:p for p in registry['portraits']}
    archive=OriginalArchive();sprites={};ids={};names={};records=[]
    for period,resource in enumerate([62,70,71,72],1):
        for index in range(200):
            original=archive.item(resource,index+1).split(b'\0')[0].decode('gbk',errors='strict').strip()
            name=corrected(original) if original else f'时期{period}保留武将{index+1}'
            photo=approved.get(name)
            if photo:
                key='photo1994/'+name
                if key not in sprites:
                    source=ROOT/photo['file']
                    if hashlib.sha256(source.read_bytes()).hexdigest()!=photo['sha256']:raise ValueError('Portrait source checksum changed: '+name)
                    image=Image.open(source).convert('RGB');w,h=image.size
                    box=tuple(int(v*(w if i%2==0 else h)) for i,v in enumerate(photo['crop']))
                    sprites[key]=ImageOps.fit(image.crop(box),(128,128),Image.Resampling.LANCZOS).convert('RGBA')
            else:
                image=archive.head(period,index)
                key='original/'+hashlib.sha256(image.tobytes()).hexdigest()[:24]
                sprites.setdefault(key,image)
            ids[f'portrait/{period}/{index}']=key;names.setdefault(name,key)
            records.append(dict(period=period,id=index,name=name,originalName=original,key=key))
    return sprites,ids,names,records

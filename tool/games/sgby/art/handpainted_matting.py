"""从统一纯色底提取原生 PNG 的透明通道，不添加人物细节或放大低分辨率图。"""
from PIL import Image, ImageFilter, ImageDraw
import numpy as np


def cutout(image, interior_holes=False):
    if image.mode=='RGBA' and image.getextrema()[3][0]<255:
        return image.copy()
    rgb=np.asarray(image.convert('RGB')).astype(np.float32)
    corners=np.concatenate([rgb[:6,:6].reshape(-1,3),rgb[-6:,:6].reshape(-1,3),rgb[:6,-6:].reshape(-1,3),rgb[-6:,-6:].reshape(-1,3)])
    key=np.median(corners,axis=0)
    red,green,blue=rgb[...,0],rgb[...,1],rgb[...,2]
    if key[1]>key[0]+60 and key[1]>key[2]+60:
        signal=green-np.maximum(red,blue)
        strength=max(1,key[1]-max(key[0],key[2]))
        broad=(green>65)&(green>red*1.5)&(green>blue*1.5)&(signal>35)
        pure=(green>190)&(signal>150)
    elif min(key[0],key[2])>key[1]+60:
        signal=np.minimum(red,blue)-green
        strength=max(1,min(key[0],key[2])-key[1])
        broad=(red>65)&(blue>65)&(np.minimum(red,blue)>green*1.5)&(signal>35)
        pure=(red>190)&(blue>190)&(signal>150)
    else:
        raise ValueError('背景不是可辨识的绿幕或品红幕，不能安全提取人物')
    # 暗幕色形成的地面投影也从画面边缘连通删除；人物内部同色衣服由墨线保护。
    connected=Image.new('L',(image.width+2,image.height+2),255)
    connected.paste(Image.fromarray((broad*255).astype(np.uint8)),(1,1))
    ImageDraw.floodfill(connected,(0,0),128)
    strong=(np.asarray(connected)[1:-1,1:-1]==128)|pure
    if interior_holes:
        # 家具的床架、桌腿及鼎耳之间有封闭空洞；只删除高饱和幕色，保留暗红木作。
        strong|=broad&(signal>90)&(red>150)&(blue>120)
    background=Image.fromarray((strong*255).astype(np.uint8))
    edge=np.asarray(background.filter(ImageFilter.MaxFilter(5)))>0
    alpha=np.ones(signal.shape,dtype=np.float32)
    alpha[strong]=0
    mixed=edge&~strong&(signal>0)
    alpha[mixed]=np.clip(1-signal[mixed]/strength,0,1)
    # 消除边缘残留的幕色；仅处理抗锯齿边缘，人物内部颜色保持原稿不变。
    safe=np.maximum(alpha,.02)
    foreground=(rgb-key[None,None,:]*(1-alpha[...,None]))/safe[...,None]
    foreground[alpha<.02]=0
    rgba=np.dstack([np.clip(foreground,0,255),np.clip(alpha*255,0,255)]).astype(np.uint8)
    return Image.fromarray(rgba,'RGBA')

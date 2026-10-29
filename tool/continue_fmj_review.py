"""续审仅更新待修改图；隐藏通过项并嵌入原批注，未审核图片逐字节保留。"""
from pathlib import Path
import argparse,copy,json,subprocess
ROOT=Path(__file__).resolve().parents[1]


def payload(path):
    text=path.read_text();start=text.index('const DATA=')+len('const DATA=');end=text.index(';\nconst $=',start)
    return json.loads(text[start:end])


def main():
    p=argparse.ArgumentParser();p.add_argument('--previous',required=True,type=Path);p.add_argument('--reviews',required=True,type=Path);p.add_argument('--patch',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--round',type=int,default=1);args=p.parse_args()
    old=payload(args.previous);feedback=json.loads(args.reviews.read_text());patch=json.loads(args.patch.read_text());reviews=feedback['reviews']
    replacements={e['id']:e for e in patch['entries']};expected={key for key,r in reviews.items()if r['status']=='需要调整'}
    assert expected<=set(replacements),expected-set(replacements)
    assert set(replacements)<={e['id']for e in old['entries']},'不能覆盖已隐藏的通过项'
    entries=[];seed={};approved=copy.deepcopy(old.get('approvedReviews',{}));unchanged=[];rechecked=[]
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    for entry in old['entries']:
        key=entry['id'];review=copy.deepcopy(reviews.get(key,{'title':entry['name'],'status':'未审核','comment':'','markers':[]}))
        if review['status']=='通过':approved[key]=review;continue
        if key in replacements:
            before=entry;entry=copy.deepcopy(replacements[key]);assert (entry['width'],entry['height'])==(before['width'],before['height']),key
            assert entry['cells']==before['cells'],key
            review['status']='待复审';review['reviewedBeforeRevision']=feedback['revision'];review['revisedAtRevision']=patch['revision'];rechecked.append(key)
        else:
            entry=copy.deepcopy(entry);unchanged.append(key)
        review['documentRevision']=revision;seed[key]=review;entries.append(entry)
    assert len(entries)+len(approved)==len(old['entries'])+len(old.get('approvedReviews',{}))
    # 批注坐标和文字保留；改的是状态和图像，不替用户标记“通过”。
    for key in rechecked:
        assert seed[key]['markers']==reviews[key]['markers']and seed[key]['comment']==reviews[key]['comment']
    for entry in entries:
        if entry['id']in unchanged:
            original=next(e for e in old['entries']if e['id']==entry['id']);assert entry['image']==original['image']
    data={'revision':revision,'renderRevision':patch['revision'],'date':'2026-10-29','mapCount':sum(bool(e['tileSize'])for e in entries),'entries':entries,'initialReviews':seed,'approvedReviews':approved,'totalCatalogCount':len(entries)+len(approved),'reviewRoundLabel':f'第{args.round}轮修订 · 原批注与审核进度已保留','exportFilename':f'伏魔记-全地图审核意见-续审{args.round}-20261029.json'}
    template=(ROOT/'tool/fmj_review_template.html').read_text();script=json.dumps(data,ensure_ascii=False,separators=(',',':')).replace('</','<\\/')
    html=template.replace('/*__REVIEW_DATA__*/','const DATA='+script+';');args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(html)
    manifest={'revision':revision,'renderRevision':patch['revision'],'visibleEntries':len(entries),'updatedThisRound':len(rechecked),'pendingRecheck':sum(r['status']=='待复审'for r in seed.values()),'unreviewedPreserved':sum(r['status']=='未审核'for r in seed.values()),'approvedHidden':len(approved),'recheckedIds':rechecked,'unchangedIds':unchanged,'approvedIds':list(approved)}
    args.output.with_suffix('.manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in manifest.items()if not isinstance(v,list)},ensure_ascii=False))


if __name__=='__main__':main()

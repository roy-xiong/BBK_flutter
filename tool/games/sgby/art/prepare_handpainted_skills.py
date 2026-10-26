"""按原版资源语义补充滚木、礌石和陷阱，避免把所有计策都绘成同一团光雾。"""
from pathlib import Path
import argparse,json


def main():
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);root=p.parse_args().root
    jobs=json.loads((root/'requests.json').read_text());known={j['id'] for j in jobs};plan=[]
    for i,(name,subject) in enumerate([
        ('log','one large heavy cut timber log lying horizontally, dark brown rough bark, a clearly visible round sawn end with natural wood growth rings, a few splintered branches, complete single log'),
        ('rock','a compact cluster of one large irregular blue-gray boulder and two smaller rocks, complete weathered stone facets, moss in small cracks, naturally rounded angular edges, clearly readable falling rocks'),
        ('trap','a small ancient Chinese wooden pitfall trap, a shallow dark earth pit framed by rough timber and several short wooden stakes, one rope loop, compact low object viewed from an elevated three-quarter angle, whole trap complete'),
    ]):
        id='effect-'+name;plan.append(id)
        if id not in known:jobs.append(dict(id=id,prompt='Fine hand-painted ancient Chinese strategy game prop, clean ink contour, natural painted materials, soft dimensional shading: '+subject+'. Exactly one isolated complete prop centered with generous empty margin. Flat uniform bright green #00ff00 background. No people, no human body, no creature, no faces, no writing, no symbols, no floor outside the object, no scenery, no border.',refs=[],kind='sprite',width=512,height=512,seed=255800+i*47))
    hail='icon-hail-final';plan.append(hail)
    if hail not in known:jobs.append(dict(id=hail,prompt='Exactly one isolated weather icon: a soft layered blue-gray cloud with SEVEN small ROUND WHITE HAILSTONES falling underneath. The hailstones are round icy white pellets with pale blue shaded facets, clearly ROUND BALLS, not teardrops and not snowflakes. Fine hand-painted Chinese game icon, dark delicate contours and soft dimensional shading, readable compact silhouette. Entire cloud and all hail pellets fit with generous margin. Uniform bright green #00ff00 background. No people, no creatures, no text, no border, no scenery.',refs=[],kind='sprite',width=512,height=512,seed=256073))
    (root/'requests.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2)+'\n');(root/'skill_jobs.json').write_text(json.dumps(plan,indent=2)+'\n')
    selected=json.loads((root/'selection.json').read_text());selected['skillEffects']={n:'effect-'+n for n in ['log','rock','trap']}
    selected['icons'].pop('fog',None);selected['icons']['hail']=hail
    (root/'selection.json').write_text(json.dumps(selected,ensure_ascii=False,indent=2)+'\n')


if __name__=='__main__':main()

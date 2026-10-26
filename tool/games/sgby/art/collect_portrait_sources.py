"""为1994版三国演义头像收集公开角色来源。只收集候选，确认后才进入正式图集。"""
from concurrent.futures import ThreadPoolExecutor, as_completed
from html import unescape
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import time
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.dart_tool/production_art/portrait_research'
WORK.mkdir(parents=True, exist_ok=True)
# 历史姓名勘误读取运行时的唯一表；孙夫人/曹睿仅为检索别名，不改游戏写法。
from portrait_assets import CORRECTIONS
ALIASES = {**CORRECTIONS, '孙尚香': '孙夫人', '曹叡': '曹睿'}

PAGE = 'https://www.tvmao.com/drama/LWMuMB0%3D/actors'
SERIES = 'https://bkso.baidu.com/item/%E3%80%8A%E4%B8%89%E5%9B%BD%E6%BC%94%E4%B9%89%E3%80%8B/7088688?fromModule=lemma_inlink'


class ImageTag(HTMLParser):
    def __init__(self):
        super().__init__()
        self.attrs = {}
    def handle_starttag(self, tag, attrs):
        if tag == 'img': self.attrs = dict(attrs)


def text(value):
    return re.sub(r'\s+', ' ', unescape(re.sub('<[^>]+>', ' ', value))).strip()


def fetch(url):
    with urlopen(Request(url, headers={'User-Agent':'Mozilla/5.0'}), timeout=18) as response:
        return response.read().decode('utf-8', errors='replace'), response.url


def cast():
    source = ROOT / '.dart_tool/production_art/tvmao_actors.html'
    if not source.exists(): source.write_text(fetch(PAGE)[0])
    data = source.read_text()
    result = {}
    for role, block in re.findall(r'<li\b[^>]*id="actor-([^"]+)"[^>]*>(.*?)</li>', data, re.S):
        match = re.search(r'title="三国演义演员表([^"]+)"', block)
        if match:
            actor = unescape(match.group(1))
        else:
            match = re.search(r'<a\b[^>]*class="black_link"[^>]*>(.*?)</a>', block, re.S)
            actor = text(match.group(1)) if match else ''
        if not actor:
            match = re.search(r'([\u4e00-\u9fff·]{2,8})\s+饰演', text(block))
            actor = match.group(1) if match else ''
        for part in re.split('[/／]', unescape(role)):
            canonical = re.sub(r'（.*?）|\(.*?\)', '', part).strip()
            if canonical and actor: result.setdefault(canonical, []).append(actor)
    # 剧集主词条的完整演员表补齐次要人物；只读取该1994版条目，不混入新版。
    series_file = ROOT / '.dart_tool/production_art/baike.html'
    if series_file.exists():
        for block in re.findall(r'<dt\b[^>]*>(.*?)</dt>', series_file.read_text(), re.S):
            plain = text(block)
            if '饰' not in plain: continue
            actor, role = [part.strip() for part in plain.split('饰', 1)]
            role = re.sub(r'（.*?）|\(.*?\)', '', role).strip()
            if re.fullmatch(r'[\u4e00-\u9fff·]{2,8}', actor) and role:
                result.setdefault(role, []).append(actor)
    result = {key: sorted(set(value)) for key,value in result.items()}
    (WORK/'cast_1994.json').write_text(json.dumps({'source':PAGE,'roles':result},ensure_ascii=False,indent=2))
    return result, data


def images(data):
    for match in re.finditer(r'<img\b[^>]*>', data, re.S|re.I):
        parser=ImageTag();parser.feed(match.group())
        attrs=parser.attrs
        url=attrs.get('data-src') or attrs.get('src','')
        if not url.startswith('http'):continue
        if 'bkimg' not in url and 'tvzhe.com' not in url:continue
        context=text(data[max(0,match.start()-500):match.end()+700])
        yield attrs.get('alt',''),url,context


def research(person, roles):
    name=person['name'];canonical=ALIASES.get(name,name)
    result={'name':name,'canonical':canonical,'actors':roles.get(canonical,[]),
            'sourcePage':'','candidates':[],'status':'searched'}
    if name.startswith('时期') or name in ['通宵虫','南方小鬼']:
        result['status']='reserved_or_special_identity';return result
    path=WORK/(canonical+'.html')
    url='https://bkso.baidu.com/item/'+quote(canonical)
    try:
        if path.exists():data=path.read_text();final=url
        else:
            data,final=fetch(url);path.write_text(data)
            time.sleep(.18)
        result['sourcePage']=final
        candidates=[]
        for alt,image_url,context in images(data):
            if not alt or any(bad in alt for bad in ['2010','新三国','游戏','真三国','动画','连环画']):continue
            actor_match=any(actor in alt for actor in result['actors'])
            score=100 if ('1994' in alt and (canonical in alt or actor_match)) else 90 if actor_match and ('三国' in alt or canonical in alt) else 70 if '三国演义' in alt and canonical in alt else 0
            if score:
                candidates.append({'caption':alt,'imageUrl':image_url,'score':score,'context':context[:650]})
        unique={item['imageUrl']:item for item in candidates}
        result['candidates']=sorted(unique.values(),key=lambda item:-item['score'])
    except Exception as error:
        result['status']='source_unavailable';result['error']=type(error).__name__;result['sourcePage']=url
    return result


def main():
    roles,cast_html=cast()
    people=json.loads((ROOT/'.dart_tool/production_art/profiles.json').read_text())['people']
    results=[]
    with ThreadPoolExecutor(max_workers=4) as pool:
        pending=[pool.submit(research,person,roles) for person in people]
        for future in as_completed(pending):
            result=future.result();results.append(result)
            if len(results)%25==0:
                (WORK/'research.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
                print('Searched',len(results),'identities; candidates for',sum(bool(r['candidates']) for r in results),flush=True)
    # 剧集本身的图集说明了版本与演员；单人剧照可直接加入候选，合照保留给人工裁剪核对。
    main_page=ROOT/'.dart_tool/production_art/baike.html'
    if main_page.exists():
        for alt,url,context in images(main_page.read_text()):
            for result in results:
                if result['canonical'] in alt and '饰' in alt:
                    result['candidates'].insert(0,{'caption':alt,'imageUrl':url,'score':100,
                                                   'sourcePage':SERIES,'context':context[:650]})
    for alt,url,context in images(cast_html):
        if '/character/' not in url:continue
        for result in results:
            if alt.startswith(result['canonical']+'（'):
                result['candidates'].insert(0,{'caption':alt,'imageUrl':url,'score':110,
                                               'sourcePage':PAGE,'context':context[:650]})
    results.sort(key=lambda result:result['name'])
    (WORK/'research.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
    print('Completed',len(results),'identities;',sum(bool(r['candidates']) for r in results),'with image candidates',flush=True)


if __name__=='__main__':main()

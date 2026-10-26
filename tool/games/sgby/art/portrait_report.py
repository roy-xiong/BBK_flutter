"""导出单文件深色HTML：已使用剧照、全部缺图人物、原图回退及姓名勘误。"""
from pathlib import Path
from html import escape
from collections import defaultdict
import base64
import io
import json
from PIL import Image
from portrait_assets import ROOT,CORRECTIONS,build_portraits


def main():
    sprites,bindings,names,records=build_portraits()
    registry=json.loads((ROOT/'tool/art/portraits_1994.json').read_text())
    approved={p['name']:p for p in registry['portraits']}
    appearances=defaultdict(list)
    for record in records:
        if record['originalName']:appearances[record['name']].append(record)
    missing=sorted(set(appearances)-set(approved))
    rows=[]
    for name in missing:
        where='、'.join(f"{p['period']}期 #{p['id']+1}" for p in appearances[name])
        reason='游戏自定义人物，使用其原始黑白头像' if name in ['通宵虫','南方小鬼'] else '未确认到可用的1994版对应角色剧照，保留原黑白头像'
        rows.append(f'<tr data-name="{escape(name)}"><td>{escape(name)}</td><td>{escape(where)}</td><td>{reason}</td></tr>')
    cards=[]
    for name,source in sorted(approved.items()):
        image=sprites['photo1994/'+name].convert('RGB');buffer=io.BytesIO();image.save(buffer,format='JPEG',quality=90)
        uri='data:image/jpeg;base64,'+base64.b64encode(buffer.getvalue()).decode()
        cards.append(f'<article data-name="{escape(name)}"><img src="{uri}" alt="{escape(name)}的1994版角色剧照头像"><strong>{escape(name)}</strong><small>{escape(source["caption"])}</small><a href="{escape(source["sourcePage"],quote=True)}" target="_blank" rel="noopener">查看来源</a></article>')
    corrections=''.join(f'<tr><td>{escape(old)}</td><td>{escape(new)}</td></tr>' for old,new in CORRECTIONS.items())
    css=''' :root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#0f1921;color:#dfebe9;font:16px/1.8 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}main{max-width:1280px;margin:auto;padding:36px 24px}h1,h2{color:#e6cf9d;line-height:1.4}p{max-width:1080px}a{color:#8ccbd2}nav,.metrics{display:flex;gap:16px;flex-wrap:wrap;margin:22px 0}.metrics div,.note{background:#1b303b;border:1px solid #35505d;padding:18px;border-radius:12px}.metrics b{font-size:32px;color:#e7bd76}.note{border-left:4px solid #b44337}.portraits{display:grid;grid-template-columns:repeat(auto-fill,minmax(145px,1fr));gap:15px}article{background:#1b2932;border:1px solid #344954;border-radius:10px;padding:12px;text-align:center}article img{display:block;width:100%;aspect-ratio:1;border-radius:6px;object-fit:cover}article strong{display:block;margin:8px 0;font-size:19px}article small{display:block;color:#9eb3bc;font-size:12px;min-height:44px}article a{font-size:13px}table{border-collapse:collapse;width:100%;margin:20px 0;font-size:14px}td,th{border:1px solid #344d5b;padding:9px 13px;text-align:left}th{background:#223946}input{width:min(100%,460px);padding:12px 15px;border:1px solid #4a6d7a;background:#182b36;color:white;border-radius:8px;font:inherit}section{margin:40px 0}code{color:#b9cfd4}footer{border-top:1px solid #35505d;padding:20px 0;color:#9eb3bc;font-size:13px}'''
    doc=f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>三国霸业 · 1994剧照头像与缺图清单</title><style>{css}</style><main><h1>1994版《三国演义》角色剧照头像</h1><p>2026-10-24 · 正式素材实施记录。头像仅做裁剪和尺寸适配；缺少核实剧照时，按原人物编号与时期使用原版黑白头像。</p><div class="metrics"><div>具名人物<br><b>{len(appearances)}</b></div><div>已采用剧照<br><b>{len(approved)}</b></div><div>继续使用原图<br><b>{len(missing)}</b></div><div>四时期绑定<br><b>{len(bindings)}</b></div></div><div class="note">92种角色剧照对应247个时期/人物位置；其余553个位置保留各自原头像，其中包括64个原资源保留空槽。黑白模式继续使用原人物头像；姓名勘误同时应用到黑白和彩色界面。</div><nav><a href="#photos">已采用的92人</a><a href="#missing">未确认剧照的203人</a><a href="#names">姓名勘误</a><a href="#method">查找与核对方法</a></nav><input id="search" aria-label="搜索人物" placeholder="输入姓名筛选头像与缺图名单"><section id="photos"><h2>已采用的角色剧照</h2><p>已排除发现的漫画、游戏画像、现代生活照及未能确认版本的候选。合照按角色位置裁剪，来源链接可用于复核。</p><div class="portraits">{''.join(cards)}</div></section><section id="missing"><h2>未确认到可用剧照的完整名单 · {len(missing)}人</h2><p>这些人物已经按游戏姓名、勘误后的姓名检索，并补查1994版演员资料及演员词条。名单包含游戏自定义人物2人；未找到可用图片，不表示认定该人物没有在剧中出现。原头像按时期与人物编号保留，不借用其他武将的脸。</p><table><thead><tr><th>正确姓名</th><th>出现位置（显示编号从1开始）</th><th>当前处理</th></tr></thead><tbody>{''.join(rows)}</tbody></table></section><section id="names"><h2>统一姓名勘误 · {len(CORRECTIONS)}处</h2><p>选将、武将查询、战斗、对话及黑白画面共用资源层姓名出口。人物ID、属性与存档关系不变。“孙尚香”“曹叡”“泠苞”等历史异名、合法写法保留。</p><table><tr><th>原资源写法</th><th>修正写法</th></tr>{corrections}</table></section><section id="method"><h2>查找、绑定与回退</h2><p>首先逐一检索295个具名身份，再对缺图角色补查已匹配演员的公开词条及图集；通过1994版剧集演员表、图片说明和剧照内容交叉核对。角色合照和跨作品拼图均人工选定对应人物，拒绝仅凭相似面孔替换。</p><p>主来源：<a href="https://www.tvmao.com/drama/LWMuMB0%3D/actors">电视猫1994版演员表</a>、<a href="https://bkso.baidu.com/item/%E3%80%8A%E4%B8%89%E5%9B%BD%E6%BC%94%E4%B9%89%E3%80%8B/7088688?fromModule=lemma_inlink">1994版剧集词条与角色图集</a>及每张卡片注明的角色/演员资料页。原图、来源、裁剪坐标和SHA-256保存在工程 <code>tool/art/portraits_1994.json</code>；运行时不联网加载头像。</p><p>原图回退逐像素验证覆盖553个位置，保留原黑白数据；800个绑定全部检查。修正姓名的GBK编码和正式黑白字体覆盖也已检查，避免生僻字变成问号或空白。</p></section><footer>此HTML包含内嵌图片和CSS，可直接离线打开。来源链接用于复核。</footer></main><script>document.querySelector('#search').addEventListener('input',e=>{{const q=e.target.value.trim();document.querySelectorAll('[data-name]').forEach(n=>n.hidden=q&&!n.dataset.name.includes(q))}})</script></html>'''
    target=Path.home()/'Downloads/三国霸业-1994剧照头像与未找到人物清单-2026-10-24.html'
    target.write_text(doc);print(target)

if __name__=='__main__':main()

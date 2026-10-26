# -*- coding: utf-8 -*-
"""已确认设计稿的可编辑矢量元素，导出工具使用，应用运行时只加载纹理图集。"""
import random, math
DEFS = '<defs>\n<linearGradient id="iron" x2=".8" y2="1"><stop stop-color="#95a9ad"/><stop offset=".35" stop-color="#4c626a"/><stop offset="1" stop-color="#192b34"/></linearGradient>\n<linearGradient id="silver" x2=".8" y2="1"><stop stop-color="#e4ece7"/><stop offset=".4" stop-color="#b0c1bf"/><stop offset="1" stop-color="#536e7c"/></linearGradient>\n<linearGradient id="gold" x2=".6" y2="1"><stop stop-color="#ead69a"/><stop offset=".4" stop-color="#bfa16a"/><stop offset="1" stop-color="#6c583b"/></linearGradient>\n<linearGradient id="cloth" x2="1" y2=".6"><stop stop-color="#715044"/><stop offset=".3" stop-color="#a96a54"/><stop offset="1" stop-color="#392f31"/></linearGradient>\n<linearGradient id="robe" x2="1" y2=".6"><stop stop-color="#d8d5b9"/><stop offset=".3" stop-color="#f0e7c8"/><stop offset=".8" stop-color="#8a9f97"/><stop offset="1" stop-color="#374f57"/></linearGradient>\n<linearGradient id="horse" x2=".8" y2="1"><stop stop-color="#bc8d5a"/><stop offset=".45" stop-color="#876044"/><stop offset="1" stop-color="#372b28"/></linearGradient>\n<linearGradient id="wood" x2="1" y2=".8"><stop stop-color="#c3a575"/><stop offset=".4" stop-color="#82634c"/><stop offset="1" stop-color="#42372f"/></linearGradient>\n<linearGradient id="stone" x2=".4" y2="1"><stop stop-color="#ded0aa"/><stop offset=".4" stop-color="#a69c83"/><stop offset="1" stop-color="#625e55"/></linearGradient>\n<radialGradient id="skin" cx=".35" cy=".25" r=".8"><stop stop-color="#f0d1a1"/><stop offset=".55" stop-color="#c79874"/><stop offset="1" stop-color="#886149"/></radialGradient>\n<linearGradient id="jade" x2="1" y2="1"><stop stop-color="#7c9b83"/><stop offset=".4" stop-color="#425f57"/><stop offset="1" stop-color="#20353b"/></linearGradient>\n<pattern id="lamella" width="18" height="17" patternUnits="userSpaceOnUse"><path d="M1 1H16V13Q8 19 1 13Z" fill="none" stroke="#d9d9b9" stroke-opacity=".38" stroke-width="1.2"/><circle cx="5" cy="4" r="1.1" fill="#e5d6ae"/><circle cx="13" cy="4" r="1.1" fill="#e5d6ae"/></pattern>\n<pattern id="masonry" width="30" height="18" patternUnits="userSpaceOnUse"><path d="M0 1H30M0 17H30M15 1V17" stroke="#352f29" stroke-opacity=".25" fill="none"/></pattern>\n<filter id="shadow" x="-.4" y="-.3" width="1.8" height="1.8"><feDropShadow dx="1" dy="5" stdDeviation="4" flood-color="#111b20" flood-opacity=".35"/></filter>\n<filter id="grain"><feTurbulence type="fractalNoise" baseFrequency=".45" numOctaves="3" seed="8" result="n"/><feColorMatrix in="n" type="saturate" values="0"/><feComponentTransfer><feFuncA type="linear" slope=".08"/></feComponentTransfer><feBlend in="SourceGraphic" mode="multiply"/></filter>\n</defs>'

def path(d, fill, stroke='#29363a', sw=2, extra=''):
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round" {extra}/>'

def rect(x, y, w, h, fill, rx=0, stroke='none', sw=1):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>'

def ellipse(x, y, rx, ry, fill, extra=''):
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}" {extra}/>'

def group(content, transform='', extra=''):
    return f'<g transform="{transform}" {extra}>{content}</g>'

def svg(body, w=400, h=400, view=None):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{view or f'0 0 {w} {h}'}">{DEFS}{body}</svg>'''

def plates(d, metal='iron'):
    return path(d, f'url(#{metal})') + path(d, 'url(#lamella)', sw=0)

def head(x, y, scale=1, helmet=True, accent='#a65345', face='#skin'):
    body = ellipse(0, 1, 24, 29, f'url({face})')
    body += path('M-24 -1Q-22 -34 0 -34Q26 -31 25 2L16 -6Q0 -14 -24 -1', 'url(#iron)' if helmet else '#332f2c')
    if helmet:
        body += path('M-25 -5Q0 -21 25 -5L25 2Q0 -10 -25 3Z', 'url(#gold)', sw=1)
        body += path('M-5 -32Q0 -58 10 -68Q7 -46 6 -31', accent, sw=1)
        body += path('M-22 3L-25 27L-16 24L-13 2M20 4L26 26L17 23L14 1', 'url(#iron)', sw=1)
    body += path('M-15 3Q-8 -2 -2 2M6 2Q13 -3 19 1', 'none', '#483b34', 2.4)
    body += path('M-13 7Q-7 6 -2 7M7 7Q13 6 18 6', 'none', '#272d2e', 1.5)
    body += ellipse(-7, 7, 1.8, 1.6, '#242e30') + ellipse(12, 7, 1.8, 1.6, '#242e30')
    body += path('M3 6L0 17L7 18M-6 24Q2 21 12 22', 'none', '#895e4c', 1.3)
    body += ellipse(-13, 15, 5, 2, '#b86d58', extra='opacity=".25"')
    return group(body, f'translate({x} {y}) scale({scale})')

def boots():
    return path('M172 259L179 328L161 345Q157 354 176 354L199 349L202 260', 'url(#iron)') + path('M217 259L228 327L249 340Q256 350 243 352L221 349L207 269', 'url(#iron)')

def footman(kind, accent='#a65345'):
    s = ellipse(206, 355, 76, 13, '#182d30', extra='opacity=".18"')
    if kind == 'elite':
        s += path('M162 117Q133 140 127 240L109 329L182 313L252 345L272 125', 'url(#cloth)')
    s += boots()
    s += path('M172 214L158 277L197 290L209 262L229 286L258 270L240 207', 'url(#iron)')
    s += plates('M162 124Q201 101 242 126L252 225Q205 247 155 224Z')
    s += path('M167 128L200 152L237 127L225 117L201 131L179 117', 'url(#gold)', sw=1)
    s += rect(158, 211, 92, 11, '#594637', 3, '#d1b47a', 1)
    s += rect(198, 211, 18, 13, 'url(#gold)', 2)
    s += plates('M158 128Q136 135 136 157L155 184L171 167Z')
    s += plates('M243 126Q266 130 270 157L251 184L236 160Z')
    s += head(202, 90, 1, True, accent)
    s += path('M250 161L267 194L286 177L292 188L271 218L245 190', 'url(#skin)')
    if kind == 'infantry':
        shield = 'M123 146L183 142L195 251L160 290L125 260Z'
        s += path(shield, 'url(#wood)', sw=3) + path('M132 158L173 154L183 247L158 276L136 255Z', 'none', '#a6b0a3', 3)
        s += path('M154 153L163 276M131 193L181 188M134 237L187 230', 'none', '#473e32', 2)
        s += path('M288 182L312 74L319 56L322 79L298 183Z', 'url(#silver)', sw=1.5)
        s += path('M279 181L307 188M292 187L285 215', 'none', 'url(#gold)', 5)
    else:
        s += plates('M142 119L171 116L181 139L170 163L135 147Z', 'silver')
        s += plates('M237 116L265 120L279 149L250 161L227 139Z', 'silver')
        s += path('M303 45L292 342', 'none', '#675042', 6)
        s += path('M299 48Q333 37 337 69Q325 68 316 82L300 77Z', 'url(#silver)')
        s += path('M300 44L306 24L310 47M295 111L318 101', 'none', 'url(#gold)', 4)
        s += path('M198 61L200 39L217 61', 'url(#gold)')
        s += path('M170 151L244 203M169 177L239 223', 'none', accent, 5)
    return s

def cavalry(accent='#a65345'):
    s = ellipse(197, 355, 155, 15, '#182d30', extra='opacity=".19"')
    s += path('M109 252L100 298L80 343L97 350L124 309L135 265M243 251L267 287L282 339L300 338L288 281L268 245', 'url(#horse)', sw=4)
    s += path('M86 238Q26 207 40 291Q55 267 58 251Q73 269 91 265', 'url(#horse)')
    s += path('M82 215Q126 190 217 208L252 200L281 134L309 128L329 166L350 180L337 197L310 196L283 250Q259 279 213 271L130 271Q84 267 82 215Z', 'url(#horse)', sw=3)
    s += path('M126 261L147 298L144 342L161 345L174 292L153 256M250 257L232 303L231 345L249 349L261 301L277 262', 'url(#horse)', sw=4)
    s += path('M278 148L270 201L287 189L302 154L307 137', 'url(#iron)', sw=1)
    s += ellipse(317, 163, 3, 4, '#181e21')
    s += path('M289 133L286 113L298 131M309 133L313 117L319 138', 'url(#horse)', sw=2)
    s += path('M303 178L335 184M301 178L234 201L196 166', 'none', '#dfce9d', 2)
    s += path('M119 207L231 207L235 247L140 253Z', 'url(#cloth)', sw=2)
    s += path('M153 211L226 213L224 238L151 243Z', 'url(#gold)', sw=1)
    s += path('M161 127L128 163L98 174L110 215L155 196L191 157', 'url(#cloth)')
    s += plates('M170 120L219 124L228 185L170 192L157 151Z')
    s += path('M176 185L207 191L204 249L183 265L169 258L179 238Z', 'url(#iron)')
    s += head(188, 91, 0.91, True, accent)
    s += path('M216 135L249 161L274 122L287 124L258 184L211 163', 'url(#skin)')
    s += path('M146 188L355 41', 'none', '#6c513a', 6)
    s += path('M350 44L371 29L364 52Z', 'url(#silver)', sw=1)
    s += path('M336 57Q321 45 307 63L329 72Z', accent, sw=1)
    s += path('M89 344L98 347M145 345L161 348M231 346L249 349M282 340L300 340', 'none', '#243137', 7)
    return s

def archer(accent='#a65345'):
    s = ellipse(192, 352, 113, 13, '#182d30', extra='opacity=".18"')
    s += path('M145 229L116 273L94 340L113 348L141 293L183 267L223 299L267 337L284 326L245 279L220 230', 'url(#jade)', sw=3)
    s += path('M93 338L83 353L115 357L124 348M263 335L277 347L302 347L284 327', 'url(#iron)', sw=3)
    s += path('M148 145L211 153L229 240L164 261L134 211Z', 'url(#wood)', sw=2)
    s += path('M148 154L206 169L215 222L161 237Z', 'url(#lamella)', sw=0)
    s += path('M126 154L113 244L92 234L102 150Z', 'url(#wood)', sw=2)
    for x in range(100, 122, 6):
        s += path(f'M{x} 199L{x - 12} 126L{x - 10} 109M{x - 12} 126L{x - 18} 119', 'none', '#d5c49c', 2)
    s += head(169, 123, 0.9, False, accent)
    s += path('M144 103L186 102L192 115L142 117Z', accent, sw=1)
    s += path('M207 163L247 183L300 173L305 186L248 201L201 186', 'url(#skin)', sw=2)
    s += path('M152 172L207 176L229 150L242 155L215 192L153 194', 'url(#skin)', sw=2)
    s += path('M309 73Q351 176 311 286', 'none', 'url(#gold)', 7)
    s += path('M310 74L274 178L312 285', 'none', '#e2dec2', 1.5)
    s += path('M229 177L366 171M364 171L353 166M364 171L354 177', 'none', '#d5c49c', 3)
    s += path('M149 200L213 224', 'none', accent, 5)
    return s

def naval(accent='#a65345'):
    s = ellipse(201, 346, 170, 19, '#4f9caa', extra='opacity=".25"')
    s += path('M63 315Q209 340 353 301M32 334Q181 366 372 328', 'none', '#d6e9d9', 4)
    s += path('M195 68L188 266', 'none', '#6a503a', 7)
    s += path('M196 76Q265 108 281 171L198 182Z', 'url(#robe)', sw=2)
    s += path('M205 94L210 170M223 104L230 167M240 117L249 163M258 135L264 160', 'none', '#a8b09a', 1)
    s += path('M58 255Q199 274 350 240L319 319Q194 356 79 314Z', 'url(#wood)', sw=4)
    s += path('M66 269Q218 301 341 257M75 289Q198 320 331 280M86 312Q211 337 321 304', 'none', '#d5bd88', 2)
    for (x, y) in [(112, 196), (209, 211), (284, 182)]:
        s += plates(f'M{x - 15} {y + 16}L{x + 19} {y + 18}L{x + 21} {y + 57}L{x - 16} {y + 55}Z')
        s += head(x, y, 0.66, True, accent)
    s += path('M72 243Q201 271 350 236', 'none', '#332e29', 9)
    for x in [96, 150, 205, 259, 317]:
        s += path(f'M{x} 244L{x} 270', 'none', '#aa8961', 6)
    s += path('M154 262L111 352M245 262L289 350', 'none', '#a6885c', 6)
    s += path('M105 344L91 362L99 370L119 352M282 344L298 367L306 360L291 342', 'url(#wood)', sw=1)
    s += path('M291 218L316 120L321 99L325 124L298 220', 'url(#silver)', sw=1)
    return s

def mystic(accent='#a65345'):
    s = ellipse(210, 355, 72, 12, '#182d30', extra='opacity=".18"')
    s += path('M174 136L226 134L244 206L266 347Q214 367 152 346L170 216Z', 'url(#robe)', sw=3)
    s += path('M199 148L189 348L215 352L216 149Z', 'url(#jade)', sw=1)
    s += path('M166 143L132 177L113 243L149 255L184 203M230 145L266 178L285 211L256 237L217 199', 'url(#robe)', sw=2)
    s += path('M165 257L172 330M232 242L241 338M189 199L172 248', 'none', '#85978b', 3)
    s += rect(168, 207, 68, 9, accent, 1)
    s += head(202, 105, 0.91, False, accent)
    s += path('M174 89L171 40L219 31L231 89Q203 79 174 89Z', 'url(#iron)', sw=3)
    s += path('M180 46L209 40L215 81L183 84Z', 'url(#jade)', sw=1)
    s += path('M197 121Q209 151 221 144L213 119', 'none', '#3c3632', 4)
    for i in range(8):
        a = -1.9 + i * 0.19
        x = 269 + math.cos(a) * 58
        y = 219 + math.sin(a) * 58
        s += path(f'M265 227Q{(x + 265) / 2 - 12} {(y + 227) / 2} {x} {y}Q{x + 13} {y + 4} 268 227', 'url(#robe)', sw=0.7)
    s += path('M108 57L109 347', 'none', '#5b5344', 5)
    s += path('M110 62Q146 57 152 73L142 126L109 120Z', accent, sw=1)
    s += path('M112 72L136 78L127 109L112 103', 'none', '#cdb78a', 2)
    s += path('M149 351Q201 332 257 350', 'none', '#9da87f', 1)
    return s

UNIT_FNS = [cavalry, lambda a: footman('infantry', a), archer, naval, lambda a: footman('elite', a), mystic]

HEROS = [('曹操', 'cao', '#d2ae86', 'narrow', 'short', 'crown', '#354e65'), ('刘备', 'liu', '#d7b68d', 'long', 'goatee', 'crown', '#557c68'), ('孙权', 'sun', '#d4a178', 'square', 'copper', 'gold', '#776d42'), ('关羽', 'guan', '#b1745d', 'long', 'long', 'wrap', '#3e6d58'), ('张飞', 'zhang', '#9c795e', 'round', 'bushy', 'band', '#3f4044'), ('赵云', 'zhao', '#ddc1a0', 'slim', 'none', 'silver', '#718e9e'), ('诸葛亮', 'zhuge', '#d9bda0', 'slim', 'thin', 'scholar', '#7a9693'), ('吕布', 'lu', '#d4ad88', 'square', 'none', 'plumes', '#895c4f')]

def portrait(spec):
    (name, key, skin, face, beard, hat, color) = spec
    r = random.Random(key)
    defs = f'<defs><radialGradient id="face" cx=".35" cy=".3" r=".75"><stop stop-color="{skin}"/><stop offset=".5" stop-color="{skin}"/><stop offset="1" stop-color="#6c5141"/></radialGradient><linearGradient id="coat" x2=".9" y2="1"><stop stop-color="{color}"/><stop offset="1" stop-color="#26383e"/></linearGradient></defs>'
    s = defs + rect(0, 0, 512, 640, '#d7d7c1')
    s += path('M0 430Q180 370 512 420V640H0Z', '#adb9a6', sw=0)
    for i in range(18):
        s += path(f'M{r.randrange(512)} 640Q{r.randrange(512)} 500 {r.randrange(512)} 120', 'none', '#ece4c8', 1, extra='opacity=".12"')
    s += path('M49 640Q50 480 168 440L205 392H311L346 443Q458 471 482 640Z', 'url(#coat)', sw=4)
    if key in ['liu', 'cao', 'guan']:
        s += path('M66 510L182 448L247 504L328 450L452 517L477 640H43Z', 'url(#coat)', sw=3)
        s += path('M184 452L242 512L201 640M327 454L260 514L301 640', 'none', '#b7b699', 3)
        if key == 'cao':
            s += plates('M64 518L167 477L188 521L150 557L55 566Z')
            s += ellipse(246, 521, 17, 21, 'url(#gold)')
        elif key == 'guan':
            s += plates('M326 474L435 513L459 565L348 555Z')
    elif hat not in ['scholar']:
        s += plates('M72 516L188 455L247 507L326 460L444 522L468 640H54Z', 'silver' if hat == 'silver' else 'iron')
        shoulder = 'silver' if key == 'zhao' else 'iron' if key == 'zhang' else 'gold'
        s += path('M64 509L132 473L194 494L170 548L62 557Z', f'url(#{shoulder})', sw=2)
        s += path('M355 483L435 512L456 557L352 551L318 506Z', f'url(#{shoulder})', sw=2)
    else:
        s += path('M132 458L242 541L344 455L372 482L252 593L100 494Z', 'url(#robe)', sw=3)
    s += path('M210 358L201 443L254 479L317 443L302 356Z', 'url(#face)', sw=3)
    s += path('M197 428L250 477L228 510L169 450M313 428L256 478L279 508L346 452', 'url(#coat)', sw=3)
    if face == 'round':
        d = 'M147 178Q117 265 148 335Q175 390 249 399Q322 394 350 326Q365 252 331 176Q250 121 147 178Z'
    elif face == 'square':
        d = 'M158 173Q137 245 150 312L178 369L235 389L299 377L337 332Q352 259 330 178Q247 133 158 173Z'
    elif face == 'long':
        d = 'M167 166Q143 231 159 314Q171 378 243 409Q306 391 333 318Q345 243 319 168Q245 125 167 166Z'
    elif face == 'narrow':
        d = 'M180 164Q151 220 173 279L161 320L197 363L254 391L302 359L324 316L312 282Q336 211 309 160Q247 122 180 164Z'
    elif key == 'zhuge':
        d = 'M182 170Q158 240 180 314Q199 371 250 406Q301 370 319 310Q334 235 311 170Q248 135 182 170Z'
    else:
        d = 'M172 171Q148 247 166 314Q184 369 248 394Q308 370 330 305Q343 235 317 167Q244 132 172 171Z'
    s += ellipse(155, 269, 21, 40, 'url(#face)') + ellipse(333, 267, 19, 36, 'url(#face)')
    if key == 'liu':
        s += ellipse(152, 293, 17, 42, 'url(#face)') + ellipse(334, 295, 15, 40, 'url(#face)')
    s += path(d, 'url(#face)', sw=3)
    s += path('M267 191Q298 232 286 271L312 294L289 312Q287 341 268 361L289 371L321 326Q339 246 315 194Z', '#7e5f4c', sw=0, extra='opacity=".26"')
    s += path('M182 313Q199 298 218 310M287 310Q308 305 320 318', 'none', '#865b49', 3, extra='opacity=".4"')
    if key in ['zhang', 'lu', 'guan']:
        s += path('M174 239L212 226L235 240L210 239L177 247Z', '#302b28', sw=1)
        s += path('M267 240L290 224L321 232L323 242L291 237Z', '#302b28', sw=1)
    elif key in ['cao', 'guan', 'zhuge']:
        if key == 'cao':
            left = 'M179 260Q206 246 232 258Q210 265 184 264Z'
            right = 'M268 259Q293 247 320 253Q296 263 273 263Z'
        elif key == 'guan':
            left = 'M174 258Q207 244 236 253Q213 262 183 264Z'
            right = 'M266 254Q294 242 326 250Q305 262 272 261Z'
        else:
            left = 'M188 257Q209 248 232 259Q209 267 188 257Z'
            right = 'M271 258Q293 247 315 257Q294 267 271 258Z'
        s += path(left, '#d4c8ae', sw=1.6) + path(right, '#d4c8ae', sw=1.6)
        s += ellipse(212, 256, 5, 5, '#253033') + ellipse(294, 254, 5, 5, '#253033')
        s += path('M183 271Q209 279 228 271M273 270Q296 276 315 266', 'none', '#86634e', 1.5)
    elif key == 'liu':
        s += path('M181 260Q206 248 231 260Q207 278 181 260Z', '#dbceb4', sw=1.1)
        s += path('M269 259Q292 247 318 258Q295 277 269 259Z', '#dbceb4', sw=1.1)
        s += ellipse(209, 260, 7, 8, '#303a36') + ellipse(293, 258, 7, 8, '#303a36')
    elif key == 'lu':
        s += path('M177 262L209 247L234 252L212 267Z', '#d3c5a6', sw=1.8)
        s += path('M270 252L292 243L322 255L291 263Z', '#d3c5a6', sw=1.8)
        s += ellipse(211, 255, 6, 7, '#282d2e') + ellipse(292, 253, 6, 7, '#282d2e')
    else:
        s += path('M177 238Q207 219 233 237L228 243Q205 232 180 246Z', '#4a3b31', sw=1)
        s += path('M267 237Q296 221 321 236L319 243Q292 233 272 244Z', '#4a3b31', sw=1)
    if key == 'zhang':
        s += ellipse(208, 259, 19, 11, '#d5c7a7') + ellipse(292, 257, 18, 11, '#d5c7a7')
        s += ellipse(212, 259, 7, 9, '#242c2d') + ellipse(291, 257, 7, 9, '#242c2d')
    else:
        s += path('M180 257Q205 244 231 257Q207 272 180 257Z', '#d0c3a7', sw=1.5)
        s += path('M269 257Q292 243 319 255Q292 271 269 257Z', '#d0c3a7', sw=1.5)
        s += ellipse(211, 256, 6, 7, '#222e30') + ellipse(293, 255, 6, 7, '#222e30')
    s += ellipse(209, 253, 1.8, 2.2, '#f3ecd4') + ellipse(291, 252, 1.8, 2.2, '#f3ecd4')
    if key == 'zhang':
        s += path('M251 257L235 289Q216 306 237 315Q257 325 278 309L266 288', 'none', '#674c3f', 3.6)
    elif key == 'sun':
        s += path('M249 248L239 286L228 302Q238 321 274 310L279 299L266 286', 'none', '#775039', 3)
    elif key == 'liu':
        s += path('M249 254L247 289Q231 303 243 313Q259 319 270 309L262 291', 'none', '#916d52', 2)
    else:
        s += path('M251 247L241 290L232 303Q245 313 265 306L272 298L263 287', 'none', '#7d5b45', 2.5)
    s += path('M247 255L248 289L257 297', 'none', '#ead2ac', 4)
    s += path('M221 340Q248 331 278 338M231 350Q251 356 273 347', 'none', '#765347', 2.5)
    if key in ['cao', 'zhuge', 'liu', 'guan']:
        for off in [0, 9]:
            s += path(f'M{180 + off} {214 - off // 2}Q214 {205 - off // 2} 236 {217 - off // 2}', 'none', '#8b6a50', 1.2, extra='opacity=".45"')
    hair = '#332e29' if beard != 'copper' else '#76503c'
    if beard != 'none':
        s += path('M244 324Q225 313 203 333L188 346Q218 340 240 333M251 325Q278 312 300 335L310 345Q280 338 257 335Z', hair, sw=1)
        if beard == 'bushy':
            bd = 'M155 297Q176 345 201 343Q243 381 300 336L333 300Q349 374 300 414L246 459L182 416Q147 376 155 297Z'
        elif beard == 'long':
            bd = 'M189 330L214 360Q249 383 291 346L308 328Q307 421 270 518L236 546L206 480Q187 407 189 330Z'
        elif beard == 'thin':
            bd = 'M232 351Q249 372 270 346L268 423L250 471L236 419Z'
        elif beard == 'goatee':
            bd = 'M219 351Q247 379 284 348L278 410L249 454L222 408Z'
        elif beard == 'copper':
            bd = 'M188 333Q197 368 211 370L216 387L233 384L250 407L271 386L287 390L300 369L318 349L301 340Q254 371 188 333Z'
        else:
            bd = 'M211 348Q249 371 288 344L276 379L250 393L219 377Z'
        s += path(bd, hair, sw=1)
        length = 172 if beard == 'long' else 90
        for i in range(16):
            x = 208 + i * 5
            s += path(f'M{x} 363Q{x + 13} {392 + length * 0.35} {245 + (i - 7) * 2} {400 + length * 0.6 - abs(i - 7) * 3}', 'none', '#b7a184', 0.8, extra='opacity=".22"')
    if hat in ['crown', 'gold']:
        s += path('M157 210Q132 134 171 118L188 77L282 65L305 110Q347 132 335 208L315 178Q249 143 172 181Z', '#282c2d', sw=3)
        s += path('M184 86L278 76L291 157L177 163Z', 'url(#gold)' if hat == 'gold' else 'url(#iron)', sw=3)
        for x in range(196, 277, 13):
            s += path(f'M{x} 87L{x + 9} 153', 'none', '#cbb37e', 2)
        s += ellipse(234, 129, 11, 15, '#759087', extra='stroke="#d5bb7c" stroke-width="3"')
        if key == 'liu':
            s += path('M155 194Q146 128 177 110Q226 91 290 113Q329 131 337 195L314 173Q242 141 168 182Z', 'url(#jade)', sw=3)
            s += path('M181 112Q241 139 308 115M172 125Q231 153 320 136', 'none', '#adb58c', 3)
            s += path('M240 99L246 56L264 57L269 105', 'url(#gold)', sw=2)
    elif hat == 'wrap':
        s += path('M154 210Q137 114 190 103Q260 84 319 129L336 211L301 184Q245 153 164 191Z', 'url(#jade)', sw=3)
        s += path('M159 181Q226 122 318 152M164 165Q243 105 315 139', 'none', '#a9b48d', 3)
        s += path('M307 141L362 184L346 290L322 220L318 151', 'url(#jade)', sw=2)
    elif hat == 'band':
        s += path('M144 216Q132 140 177 107Q252 80 326 133L345 213L317 183Q233 164 160 199Z', '#302b28', sw=3)
        s += path('M145 192Q230 141 338 184L337 206Q231 168 148 216Z', 'url(#cloth)', sw=3)
        s += path('M151 191L129 203L113 264L145 239Z', 'url(#cloth)', sw=2)
    elif hat == 'silver':
        s += path('M149 220Q125 139 168 105L214 73L262 65L305 103Q353 132 341 220L312 190Q231 158 166 194Z', 'url(#silver)', sw=3)
        s += path('M224 73L248 47L265 171L247 198L230 175Z', 'url(#silver)', sw=2)
        s += path('M149 197L133 286L158 319L174 249M326 194L352 280L326 316L312 249', 'url(#silver)', sw=3)
        s += path('M238 70Q223 16 277 8Q257 38 270 72', 'url(#robe)', sw=2)
    elif hat == 'scholar':
        s += path('M155 211L153 129L172 106L169 47L308 45L312 100L335 127L333 211L310 177Q252 147 176 183Z', 'url(#iron)', sw=3)
        s += path('M188 57L287 57L293 139L190 151Z', 'url(#jade)', sw=3)
        for i in range(9):
            s += path(f'M{195 + i * 10} 63L{198 + i * 10} 135', 'none', '#7f9d8d', 1)
        for i in range(8):
            x = 349 + i * 12
            y = 461 - abs(i - 3) * 12
            s += path(f'M374 604Q{x - 36} {y + 40} {x} {y}Q{x + 31} {y + 10} 379 604', 'url(#robe)', sw=1)
    elif hat == 'plumes':
        s += path('M150 213Q130 130 177 109L228 90L292 110Q348 125 342 213L317 185Q246 150 168 191Z', 'url(#gold)', sw=3)
        s += path('M153 181L336 178L335 206L156 210Z', 'url(#iron)', sw=2)
        s += path('M222 174L251 124L279 174L253 200Z', 'url(#gold)', sw=2)
        for sign in [-1, 1]:
            s += path(f'M{250 + sign * 35} 128Q{250 + sign * 120} 88 {250 + sign * 90} 13', 'none', '#4c4032', 7)
            for i in range(7):
                s += path(f'M{250 + sign * (45 + i * 8)} {107 - i * 12}l{sign * 25} -14', 'none', '#aa8c57', 3)
    if key == 'zhang':
        s += path('M312 278L299 300M313 282L304 302', 'none', '#714f43', 2)
    return s

def city(capital=False, harbor=False):
    s = ellipse(164, 222, 145, 20, '#172c2e', extra='opacity=".18"')
    s += path('M32 139L162 107L288 139L285 212L164 239L35 209Z', 'url(#stone)', sw=2)
    s += path('M34 150L164 120L283 151L281 209L164 234L38 207Z', 'url(#masonry)', sw=0)
    s += path('M145 239V199Q164 171 184 195V234Z', '#303c3c', sw=2)
    s += path('M147 201Q165 178 182 198V235L164 239L149 235Z', 'url(#wood)', sw=1)
    for (x, y) in [(44, 139), (266, 139), (151, 112)]:
        s += path(f'M{x - 16} {y - 39}L{x + 17} {y - 39}L{x + 19} {y + 27}L{x - 18} {y + 27}Z', 'url(#stone)', sw=2)
        s += path(f'M{x - 27} {y - 34}L{x} {y - 53}L{x + 29} {y - 34}L{x + 21} {y - 30}L{x - 20} {y - 30}Z', 'url(#iron)', sw=2)
        s += rect(x - 7, y - 24, 13, 21, '#3c4946', 3)
    s += path('M92 132L92 81L164 57L236 83V130Z', 'url(#stone)', sw=2)
    s += path('M75 85L165 43L253 84L241 93L166 66L87 95Z', 'url(#iron)', sw=2)
    s += path('M86 86L166 54L241 85', 'none', '#bdac75', 3)
    for x in [111, 139, 169, 198, 219]:
        s += rect(x, 100, 10, 17, '#394b48', 2)
    if capital:
        s += path('M132 62L133 33L167 20L199 36V63', 'url(#stone)', sw=2)
        s += path('M119 36L165 5L213 36L203 41L166 23L130 43Z', 'url(#iron)', sw=2)
    s += path('M257 96L257 18', 'none', '#6b5a41', 3)
    s += path('M259 18Q287 11 297 27L284 57L259 50Z', '#a35343', sw=1)
    if harbor:
        s += path('M40 221L6 242M61 225L26 250', 'none', '#8c7352', 7)
        s += path('M12 238L61 246L51 259L17 256Z', 'url(#wood)', sw=1)
    return s

def tree(x, y, scale=1):
    t = ellipse(0, 17, 14, 5, '#233a35', extra='opacity=".22"')
    t += path('M-2 1L-1 19L4 19L2 -5', 'url(#wood)', sw=0.8)
    t += path('M-17 3Q-21 -5 -12 -10Q-16 -22 -5 -24Q-1 -36 7 -26Q18 -28 17 -15Q27 -8 18 2Q7 12 -17 3Z', 'url(#jade)', sw=0.7)
    t += path('M-11 -13Q-1 -22 8 -14M-9 -3Q2 -10 13 -4', 'none', '#a0af80', 1, extra='opacity=".45"')
    return group(t, f'translate({x} {y}) scale({scale})')

# -*- coding: utf-8 -*-
"""离线生成沿陆地的原版城池连接线，应用和CI只消费结果JSON。"""
import json,math,heapq
from pathlib import Path
from shapely.geometry import shape,Point,LineString
from shapely.prepared import prep

def routes(cities,links):
    land=shape(json.loads((Path(__file__).parent/'land.geojson').read_text()))
    prepared=prep(land);cache={};step=.12
    def xy(n):return (97+n[0]*step,20+n[1]*step)
    def valid(n):
        if n not in cache:cache[n]=prepared.covers(Point(*xy(n)))
        return cache[n]
    def nearest(point):
        origin=(round((point[0]-97)/step),round((point[1]-20)/step))
        for radius in range(8):
            choices=[(origin[0]+dx,origin[1]+dy) for dx in range(-radius,radius+1) for dy in range(-radius,radius+1)]
            choices.sort(key=lambda n:math.dist(xy(n),point))
            for n in choices:
                if valid(n) and prepared.covers(LineString([point,xy(n)])):return n
    def route(start,end):
        if prepared.covers(LineString([start,end])):return [start,end]
        first,last=nearest(start),nearest(end)
        if first is None or last is None:return []
        queue=[(0,first)];cost={first:0};previous={};found=False
        while queue and len(cost)<40000:
            _,node=heapq.heappop(queue)
            if node==last:found=True;break
            for dx,dy in [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]:
                n=(node[0]+dx,node[1]+dy)
                if n[0]<0 or n[1]<0 or n[0]>267 or n[1]>200 or not valid(n):continue
                value=cost[node]+math.hypot(dx,dy)
                if value>=cost.get(n,float('inf')) or not prepared.covers(LineString([xy(node),xy(n)])):continue
                cost[n]=value;previous[n]=node;heapq.heappush(queue,(value+math.dist(n,last),n))
        if not found:return []
        points=[end,xy(last)];node=last
        while node!=first:node=previous[node];points.append(xy(node))
        points.append(start);points.reverse();return points
    result=[]
    for a in range(len(cities)):
        for b in links[a*16:a*16+8]:
            b-=1
            if b<=a or b>=len(cities):continue
            ca,cb=cities[a],cities[b]
            points=route((ca['lon'],ca['lat']),(cb['lon'],cb['lat']))
            if points:result.append({'a':a,'b':b,'points':[[round((32+(lon-97)/32*1180)/1280*240,5),round((78+(44-lat)/24*820)/960*144,5)] for lon,lat in points]})
    return result

import json, math, sys
R=6371000
def hav(a,b):
    la1,lo1=map(math.radians,a); la2,lo2=map(math.radians,b)
    h=math.sin((la2-la1)/2)**2+math.cos(la1)*math.cos(la2)*math.sin((lo2-lo1)/2)**2
    return 2*R*math.asin(math.sqrt(h))
def bearing(a,b):
    la1,lo1=map(math.radians,a); la2,lo2=map(math.radians,b)
    y=math.sin(lo2-lo1)*math.cos(la2); x=math.cos(la1)*math.sin(la2)-math.sin(la1)*math.cos(la2)*math.cos(lo2-lo1)
    return (math.degrees(math.atan2(y,x))+360)%360
go=json.load(open(sys.argv[1]))['data']; back=json.load(open(sys.argv[2]))['data']
route=[(c['y'],c['x']) for c in go['Coordinates']]
def ridx(p): return min(range(len(route)),key=lambda i:hav(route[i],p))
out=[]
for t in go['SpeedTunnels']:
    s=(t['startLatY'],t['startLonX']); e=(t['endLatY'],t['endLonX'])
    c=[(p['y'],p['x']) for p in t['coordinates']]
    if hav(c[0],s)>hav(c[0],e): c=c[::-1]          # izi giriş->çıkış yönüne çevir
    L=sum(hav(c[i],c[i+1]) for i in range(len(c)-1))
    # giriş yönü: izde girişten ~150 m sonraki noktaya
    acc=0;j=1
    while j<len(c)-1 and acc+hav(c[j-1],c[j])<150: acc+=hav(c[j-1],c[j]); j+=1
    b=bearing(s,c[j])
    # izi ~50 m aralıkla seyrelt
    tr=[c[0]];acc=0
    for i in range(1,len(c)):
        acc+=hav(c[i-1],c[i])
        if acc>=50 or i==len(c)-1: tr.append(c[i]);acc=0
    fwd=ridx(s)<ridx(e)
    out.append({
        'id':f"icisleri-{t['id']}",'name':' '.join(t['name'].split()),
        'startLat':s[0],'startLng':s[1],'startBearing':round(b,1),
        'endLat':e[0],'endLng':e[1],'limitKmh':t['speedLimit'],'lengthM':round(L),
        'track':[[round(p[0],6),round(p[1],6)] for p in tr],
        # Ek alanlar (Corridor.fromJson bunları yok sayar)
        'source':'icisleri.gov.tr PolGenControlPointV2/CreateRoute','sourceId':t['id'],
        'officialLengthKm':t['length'],'vehicleType':t['vehicleType'],
        'yon':'Ankara→İzmir' if fwd else 'İzmir→Ankara',
        'rotaSirasi':ridx(s) if fwd else None,
    })
out.sort(key=lambda x:(x['yon']!='Ankara→İzmir', x['rotaSirasi'] or 0))
for o in out: o.pop('rotaSirasi')
json.dump(out,open(sys.argv[3],'w'),ensure_ascii=False,indent=1)
for o in out: print(o['yon'],o['id'],o['name'],o['limitKmh'],'%.1fkm'%(o['lengthM']/1000),'resmi',o['officialLengthKm'],'yön',o['startBearing'],'iz',len(o['track']))

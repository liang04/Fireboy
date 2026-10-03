"""Two clear portal pairs, a remote keeper, and a partner-opened reunion route."""
def build(Grid, base):
    g=Grid(50,24);g.border();g.rect(1,21,48,23,'#')
    g.rect(4,12,20,13,'#')
    g.rect(24,21,26,22,'~');g.rect(31,21,33,22,'^')
    g.rect(38,8,48,23,'#')
    g.put(3,20,'F');g.put(6,20,'W');g.put(45,7,'E');g.put(47,7,'Q')
    objects=[
        {'type':'portal','cell':[2,20],'pair':'P1'},
        {'type':'portal','cell':[6,11],'pair':'P1'},
        {'type':'plate','cell':[12,11],'channel':'A'},
        {'type':'door','cell':[16,14],'height':7,'channel':'A'},
        {'type':'lever','cell':[22,20],'channel':'B'},
        {'type':'door','cell':[14,5],'height':7,'channel':'B'},
        {'type':'portal','cell':[36,20],'pair':'P2'},
        {'type':'portal','cell':[40,7],'pair':'P2'},
        {'type':'gem','cell':[4,11],'color':'red'},
        {'type':'gem','cell':[32,22],'color':'red'},
        {'type':'gem','cell':[46,7],'color':'red'},
        {'type':'gem','cell':[8,20],'color':'blue'},
        {'type':'gem','cell':[25,22],'color':'blue'},
        {'type':'gem','cell':[44,7],'color':'blue'},
    ]
    return dict(base,grid=g.rows(),objects=objects,revision=base['revision']+1,
        subtitle='P1 通往观察台：先遣者守 A，伙伴在下层拉 B 接应；最后经 P2 到会合高台。',par_time=30.0)

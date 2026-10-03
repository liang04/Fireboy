"""Short elemental lesson followed by a single gentle keeper-and-return handoff."""
def build(Grid, base):
    g=Grid(54,23);g.border();g.rect(1,20,52,22,'#')
    g.rect(12,20,14,21,'^');g.rect(28,20,30,21,'~')
    g.row(18,32,33,'#');g.row(16,34,50,'#');g.row(17,34,50,'#')
    g.row(16,37,44,'^')
    g.put(52,18,'#')  # A missed jump drops onto safe ground; step back to the bridge.
    g.put(3,19,'F');g.put(6,19,'W');g.put(50,15,'E');g.put(47,19,'Q')
    objects=[
        {'type':'plate','cell':[46,15],'channel':'A'},
        {'type':'door','cell':[36,18],'height':2,'channel':'A'},
        {'type':'lever','cell':[42,19],'channel':'B'},
        {'type':'door','cell':[50,15],'height':1,'channel':'B'},
        {'type':'gem','cell':[12,21],'color':'red'},
        {'type':'gem','cell':[14,21],'color':'red'},
        {'type':'gem','cell':[39,16],'color':'red'},
        {'type':'gem','cell':[28,21],'color':'blue'},
        {'type':'gem','cell':[30,21],'color':'blue'},
        {'type':'gem','cell':[43,19],'color':'blue'},
    ]
    return dict(base,grid=g.rows(),objects=objects,revision=base['revision']+1,
        subtitle='先认识浅池。最后火娃走熔岩小桥守 A，水娃从桥下拉 B 接应。',par_time=30.0)

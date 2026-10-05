"""Two-stage rechargeable cargo relay with a safe loading apron and full well receiver."""
def build(Grid, base):
    g = Grid(48, 20); g.border(); g.row(0,1,46,'#')
    g.rect(1,12,46,19,'#'); g.rect(25,12,29,18,'.')
    for x1,x2,y in [(8,9,10),(10,11,8),(12,34,6),(35,36,8),(37,38,10),(27,29,3),(31,33,4)]:
        g.row(y,x1,x2,'#')
    g.put(10,11,'F');g.put(39,11,'W');g.put(3,11,'E');g.put(44,11,'Q')
    objects=[
        {'type':'box','cell':[12,11]},
        # Both partners prepare the high loading key; the crate cannot climb here.
        {'type':'double_plate','cells':[[17,5],[34,5]],'channel':'K'},
        {'type':'door','cell':[14,7],'height':5,'channel':'K'},
        # Stage one: leave the box on the wide, dry apron before changing the keeper.
        {'type':'delayed_plate','cell':[21,5],'channel':'H','delay_seconds':6.0},
        {'type':'door','cell':[15,7],'height':5,'channel':'H','safe_close':True},
        # Stage two is independently rechargeable, so an early release loses no cargo.
        {'type':'delayed_plate','cell':[32,3],'channel':'J','delay_seconds':6.0},
        {'type':'door','cell':[24,7],'height':5,'channel':'J','safe_close':True},
        {'type':'plate','cell':[25,18],'channel':'A','width':5},
        {'type':'door','cell':[6,0],'height':12,'channel':'A'},
        {'type':'door','cell':[42,0],'height':12,'channel':'A'},
        # All five receiving cells count, including either wall. People can return unconditionally.
        {'type':'portal','cell':[28,18],'pair':'R1'},
        {'type':'portal','cell':[28,2],'pair':'R1'},
        {'type':'gem','cell':[11,11],'color':'red'},
        {'type':'gem','cell':[17,5],'color':'red'},
        {'type':'gem','cell':[3,11],'color':'red'},
        {'type':'gem','cell':[39,11],'color':'blue'},
        {'type':'gem','cell':[32,3],'color':'blue'},
        {'type':'gem','cell':[44,11],'color':'blue'},
    ]
    return dict(base,name='10 - 合力投递',
        subtitle='先在高桥同踩 K 备货，再分工：H 送箱到中转台，J 放行入井。离板留 6 秒，超时可重充；误落走 R1。',
        par_time=70.0,camera_margin=240.0,grid=g.rows(),objects=objects,revision=int(base.get('revision',1))+2)

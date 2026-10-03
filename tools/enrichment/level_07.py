"""A dry, recoverable box elevator outing followed by the asymmetric final hold."""
def build(Grid, base):
    g=Grid(52,22); g.border(); g.rect(1,20,50,21,'#'); g.row(19,1,28,'#')
    g.rect(29,12,50,21,'#')
    # Missed rides land on the continuous loading floor, ready for another pass.
    # Small scenic stepping stones are optional; they do not move the box.
    g.row(17,17,18,'='); g.row(15,21,22,'=')
    g.put(41,11,'#')
    g.put(3,18,'F'); g.put(6,18,'W'); g.put(43,11,'E'); g.put(48,11,'Q')
    objects=[
        {'type':'lever','cell':[9,18],'channel':'A'},
        {'type':'door','cell':[12,12],'height':7,'channel':'A'},
        {'type':'box','cell':[20,18]},
        {'type':'moving_platform','from':[24,19],'to':[24,12],'width':5,'speed':90},
        {'type':'plate','cell':[32,11],'channel':'B'},
        {'type':'door','cell':[35,5],'height':7,'channel':'B'},
        {'type':'plate','cell':[41,10],'channel':'D'},
        {'type':'door','cell':[45,5],'height':7,'channel':'D'},
        {'type':'gem','cell':[5,18],'color':'red'},
        {'type':'gem','cell':[27,11],'color':'red'},
        {'type':'gem','cell':[39,11],'color':'red'},
        {'type':'gem','cell':[16,18],'color':'blue'},
        {'type':'gem','cell':[22,14],'color':'blue'},
        {'type':'gem','cell':[34,11],'color':'blue'},
    ]
    return {'name':'7 - 一路同行','subtitle':'没有危险的散步：把箱子送上电梯、推到楼上压 B，最后我替你守住出口门。错过电梯也能安全再来。','par_time':40.0,'revision':base['revision']+1,'grid':g.rows(),'objects':objects}

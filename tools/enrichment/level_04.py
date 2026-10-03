"""A live holder admits the courier; the courier brings a box back to replace them."""
def build(Grid, base):
    g=Grid(62,24); g.border(); g.rect(1,21,60,23,'#')
    g.rect(19,21,25,22,'*'); g.rect(40,21,45,22,'^')
    g.row(20,54,59,'#'); g.rect(33,17,44,18,'#'); g.row(19,31,32,'#')
    g.put(2,20,'F'); g.put(5,20,'W'); g.put(57,19,'E'); g.put(44,16,'Q')
    objects=[
        {'type':'plate','cell':[6,20],'channel':'A'},
        {'type':'door','cell':[10,14],'height':7,'channel':'A'},
        {'type':'box','cell':[14,20]},
        {'type':'moving_platform','from':[18,19],'to':[26,19],'width':3,'speed':90},
        {'type':'plate','cell':[32,20],'channel':'B'},
        {'type':'door','cell':[36,19],'height':3,'channel':'B'},
        {'type':'lever','cell':[48,20],'channel':'C'},
        {'type':'door','cell':[42,13],'height':5,'channel':'C'},
        # Acid separates the sole box from the final plates; the elevated one
        # additionally has a two-step ascent that boxes cannot climb.
        {'type':'double_plate','cells':[[47,20],[38,16]],'channel':'K'},
        {'type':'door','cell':[53,15],'height':7,'channel':'K'},
        {'type':'gem','cell':[42,22],'color':'red'},
        {'type':'gem','cell':[48,20],'color':'red'},
        {'type':'gem','cell':[56,19],'color':'red'},
        {'type':'gem','cell':[30,20],'color':'blue'},
        {'type':'gem','cell':[36,16],'color':'blue'},
        {'type':'gem','cell':[43,16],'color':'blue'},
    ]
    return {'name':'4 - 时序接力','subtitle':'先替队友守 A，让他从门后送回木箱接班；后段换人守 B，终点仍要同时踩双钥匙板。','par_time':45.0,'revision':base['revision']+1,'grid':g.rows(),'objects':objects}

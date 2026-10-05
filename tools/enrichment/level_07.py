"""L7: a short dry promenade and an optional cooperative sightseeing loop."""
def build(Grid, base):
    g = Grid(48, 23)
    g.border(); g.rect(1,20,46,22,'#')
    # The main path is a continuous, hazard-free walk. Scenic lift landings sit
    # well above jump range; missed rides always return to the same dry floor.
    g.row(11,12,35,'#')
    g.row(8,21,26,'=')
    g.put(3,19,'F'); g.put(6,19,'W')
    g.put(42,19,'E'); g.put(44,19,'Q')
    objects = [
        {'type':'plate','cell':[17,19],'channel':'A'},
        {'type':'moving_platform','from':[8,18],'to':[8,11],'width':4,'speed':100,'channel':'A'},
        # The first sightseer enables a second, independent lift for their
        # friend. Roles can swap; neither coloured character is prescribed.
        {'type':'lever','cell':[15,10],'channel':'B'},
        {'type':'moving_platform','from':[36,18],'to':[36,11],'width':4,'speed':100,'channel':'B'},
        {'type':'gem','cell':[5,19],'color':'red'},
        {'type':'gem','cell':[18,10],'color':'red'},
        {'type':'gem','cell':[22,7],'color':'red'},
        {'type':'gem','cell':[41,19],'color':'red'},
        {'type':'gem','cell':[10,19],'color':'blue'},
        {'type':'gem','cell':[30,10],'color':'blue'},
        {'type':'gem','cell':[25,7],'color':'blue'},
        {'type':'gem','cell':[43,19],'color':'blue'},
    ]
    return dict(base, name='7 - 一路同行',
        subtitle='一路平地，没有危险。想看风景就替伙伴踩 A；楼上拉 B 接你同游，宝石在观景台。错过电梯也能安全再来。',
        par_time=70.0, revision=base.get('revision',1)+2, grid=g.rows(), objects=objects)

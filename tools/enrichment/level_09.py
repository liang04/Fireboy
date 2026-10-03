"""A midpoint master switch followed by two genuinely elemental roof repairs."""

def build(Grid, base):
    g = Grid(84, 24)
    g.border()
    g.row(0, 1, 82, '#')
    g.rect(1, 21, 82, 23, '#')
    g.rect(24, 21, 31, 22, '*')
    # Two sealed service tunnels. Their repair levers are INSIDE the fluid,
    # not on a dry endpoint that the wrong actor could approach from above.
    g.row(13, 45, 59, '#')
    g.rect(47, 0, 55, 10, '#')
    g.rect(47, 11, 55, 12, '~')
    g.rect(47, 14, 55, 18, '#')
    g.rect(47, 19, 55, 20, '^')
    g.rect(63, 6, 76, 7, '#')
    g.put(3, 20, 'F')
    g.put(6, 20, 'W')
    g.put(69, 5, 'E')
    g.put(70, 5, 'Q')
    objects = [
        {'type':'box', 'cell':[10,20]},
        {'type':'plate', 'cell':[15,20], 'channel':'A'},
        {'type':'door', 'cell':[19,0], 'height':21, 'channel':'A'},
        {'type':'moving_platform', 'from':[22,19], 'to':[33,19], 'width':3, 'speed':95},
        # M is the halfway point. It opens the service area and its upper access lift.
        {'type':'lever', 'cell':[41,20], 'channel':'M'},
        {'type':'door', 'cell':[44,0], 'height':21, 'channel':'M'},
        {'type':'moving_platform', 'from':[41,19], 'to':[41,13], 'width':3, 'speed':110, 'channel':'M'},
        {'type':'lever', 'cell':[53,20], 'channel':'R'},
        {'type':'lever', 'cell':[53,12], 'channel':'B'},
        {'type':'moving_platform', 'from':[77,19], 'to':[77,6], 'width':3, 'speed':130, 'channel':'R'},
        {'type':'moving_platform', 'from':[60,11], 'to':[60,6], 'width':3, 'speed':110, 'channel':'B'},
        # Each approach stops before the central shared roof until BOTH repairs.
        # Riding one lift together cannot bypass the other element's repair.
        {'type':'door', 'cell':[67,0], 'height':6, 'channel':'R'},
        {'type':'door', 'cell':[72,0], 'height':6, 'channel':'B'},
        {'type':'gem', 'cell':[8,20], 'color':'red'},
        {'type':'gem', 'cell':[35,20], 'color':'red'},
        {'type':'gem', 'cell':[50,20], 'color':'red'},
        {'type':'gem', 'cell':[75,5], 'color':'red'},
        {'type':'gem', 'cell':[11,20], 'color':'blue'},
        {'type':'gem', 'cell':[38,20], 'color':'blue'},
        {'type':'gem', 'cell':[50,12], 'color':'blue'},
        {'type':'gem', 'cell':[64,5], 'color':'blue'},
    ]
    # Verified all-gem Input replay: 24.50 s. 55 s allows 55.50 s for
    # human reading, coordination and lift timing; it is not a speedrun cutoff.
    return {'name':'9 - 总闸·双路修复',
            'subtitle':'总闸只到半程：火娃进熔岩检修 R，水娃进水道检修 B。两路都修好，才能在屋顶会合。',
            'par_time':55.0, 'grid':g.rows(), 'objects':objects,
            'revision':int(base.get('revision',1))+1}

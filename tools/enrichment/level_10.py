"""Two-person gravity delivery with an unconditional, player-only well escape."""

def build(Grid, base):
    g = Grid(38, 20)
    g.border()
    g.row(0, 1, 36, '#')
    g.rect(1, 12, 36, 19, '#')
    g.rect(16, 12, 20, 18, '.')
    # Human stairs and upper footbridge never carry the ground-level cargo upward.
    g.row(10, 8, 9, '#')
    g.row(8, 10, 11, '#')
    g.row(6, 12, 23, '#')
    g.row(3, 18, 20, '#')
    g.row(8, 24, 25, '#')
    g.row(10, 26, 27, '#')
    g.put(10, 11, 'F')
    g.put(29, 11, 'W')
    g.put(3, 11, 'E')
    g.put(35, 11, 'Q')
    objects = [
        {'type':'box', 'cell':[12,11]},
        # H is intentionally on a six-cell-high bridge. Boxes cannot climb stairs.
        {'type':'plate', 'cell':[21,5], 'channel':'H'},
        {'type':'door', 'cell':[15,8], 'height':4, 'channel':'H'},
        # The box falls seven cells onto a full-width receiving plate.
        # Nudging delivered cargo sideways must not strand it behind the rescue portal.
        # A person may press A, but cannot leave it on.
        {'type':'plate', 'cell':[16,18], 'channel':'A', 'width':5},
        {'type':'door', 'cell':[6,0], 'height':12, 'channel':'A'},
        {'type':'door', 'cell':[32,0], 'height':12, 'channel':'A'},
        # These portals have no channel. Fallen people recover independently;
        # Portal only accepts Player, so cargo cannot leave the well this way.
        {'type':'portal', 'cell':[19,18], 'pair':'R1'},
        {'type':'portal', 'cell':[19,2], 'pair':'R1'},
        {'type':'gem', 'cell':[11,11], 'color':'red'},
        {'type':'gem', 'cell':[17,5], 'color':'red'},
        {'type':'gem', 'cell':[3,11], 'color':'red'},
        {'type':'gem', 'cell':[29,11], 'color':'blue'},
        {'type':'gem', 'cell':[21,5], 'color':'blue'},
        {'type':'gem', 'cell':[35,11], 'color':'blue'},
    ]
    # Verified all-gem Input replay: 10.75 s. 35 s allows 24.25 s for
    # role assignment, looking into the well and cautious delivery; pending human playtest.
    return {'name':'10 - 合力投递',
            'subtitle':'一人持续踩住高桥 H 板，另一人送箱入井。箱压 A 板放行左右归途；失足可走井底传送门。',
            'par_time':35.0, 'camera_margin':240.0, 'grid':g.rows(), 'objects':objects,
            'revision':int(base.get('revision',1))+1}

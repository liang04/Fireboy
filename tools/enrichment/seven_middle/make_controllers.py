"""Readable construction of deterministic waypoint controllers; they only drive Input."""
import json
from pathlib import Path
HERE=Path(__file__).resolve().parent

def go(x,y,**kw):return dict(kind='go',x=x,y=y,**kw)
def jump(x,y,**kw):return dict(kind='jump',x=x,y=y,**kw)
def swim(x,y,**kw):return dict(kind='swim',x=x,y=y,**kw)
def wait(frames):return dict(kind='wait',frames=frames)
def interact():return dict(kind='interact')
def board(n):return dict(kind='board',platform=n,range=145,timeout=2400)
def ride(y):return dict(kind='ride',until=y,timeout=2400)
def push(x):return dict(kind='push',box_x=x,timeout=2400)
def phase(label,fire=(),water=()):return dict(label=label,fire=list(fire),water=list(water))
def route(n,phases,**kw):return dict(level=n,verify_store=True,max_frames=18000,phases=phases,**kw)
def save(name,data):(HERE/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')

l7=[phase('Choose the optional sightseeing trip',[go(5,19),go(7,19)],[go(10,19),go(17,19)]),
    phase('A keeper sends first sightseer',[board(0),ride(370),jump(14,10),go(15,10),interact()]),
    phase('B lift brings the keeper; explore first balcony',[go(18,10),go(20,10),jump(22,7,rise_first=True),go(28,10)],[go(35,19),board(1),ride(370),jump(33,10),go(30,10)]),
    phase('Upper viewpoint and the safe walking return',[go(41,19)],[go(28,10),jump(25,7,rise_first=True),go(28,10),go(43,19)]),
    phase('Meet at the promenade exits',[go(42,19)],[go(44,19)])]
save('controllers_07.json',[route(7,l7)])

l6=[phase('Left branch first with a hub keeper',[dict(kind='go',x=6,y_less=450),go(10,11),go(16,13),swim(20,11),go(20,11)],[go(16,20)]),
    phase('Return through P1; change keeper for P2',[jump(13,11),go(9,11),go(6,20),go(34,20)],[go(44,11),go(41,11),go(37,13),swim(33,11),go(30,11)]),
    phase('Both keys stay lit during return and gem exchange',[],[go(33,11),swim(41,11),go(44,20),go(6,11),jump(10,11),go(13,11),jump(20,11),go(21,11)]),
    phase('Visit the other fixed branch',[go(44,11),jump(41,11),jump(34,11),go(31,11)],[go(20,11),jump(13,11),go(9,11),go(6,20),go(47,20)]),
    phase('Return to hub and take the two-key exit',[go(34,11),jump(41,11),go(44,20),go(57,20)],[go(59,20)])]
save('controllers_06.json',[route(6,l6)])

l5=[phase('Element detours and choose freight loading',[jump(5,24),go(3,27),swim(6,25),go(9,25)],[go(30,25)]),
    phase('Load the existing A freight lift',[push(17)]),
    phase('Escort cargo to the wide B landing',[ride(666),push(18),jump(21,18)],[go(32,25)]),
    phase('Scout enables the keeper return lift',[go(22,18),interact(),go(24,18)]),
    phase('Keeper visits water cove and takes C; scout waits for summit',[go(30,18)],[go(33,25),jump(35,24),go(37,27),swim(40,25),go(45,25),board(1),ride(626),jump(43,18),go(35,18)]),
    phase('Join the cargo-powered summit lift',[go(45,18),board(2),ride(306),jump(43,8),go(33,8),jump(30,5,rise_first=True),go(28,5),go(33,8)],[go(45,18),board(2),ride(306),jump(43,8),go(39,8),go(33,8),jump(30,5,rise_first=True),go(39,8)])]
save('controllers_05.json',[route(5,l5)])

l6_other=[
    phase('Choose the right branch first',[go(34,20)],[go(44,11),go(41,11),go(37,13),swim(33,11),go(30,11)]),
    phase('Return to the hub and hand over the keeper role',[go(6,11),go(10,11),go(16,13),swim(20,11),go(20,11)],[go(33,11),swim(41,11),go(44,20),go(16,20)]),
    phase('Revisit opposite fixed branches for the optional gems',[jump(13,11),go(9,11),go(6,20),go(44,11),jump(41,11),jump(34,11),go(31,11)],[go(6,11),jump(10,11),go(13,11),jump(20,11),go(21,11)]),
    phase('Two independent return loops to the shared exit',[go(34,11),jump(41,11),go(44,20),go(57,20)],[go(20,11),jump(13,11),go(9,11),go(6,20),go(59,20)])]
save('alternate_06.json',[route(6,l6_other)])
l6_recover=[
    phase('Scout arrives before the keeper',[dict(kind='go',x=6,y_less=450),go(10,11),go(16,13),swim(20,11),go(20,11)],[wait(100)]),
    phase('Return without a key; the keeper arrives too late',[jump(13,11),go(9,11),go(6,20),go(9,20)],[go(16,20)]),
    phase('Use the same portal again and meet the keeper',[go(6,11),go(10,11),go(13,11),jump(20,11),go(20,11)]),
    *l6[1:]]
save('recovery_06.json',[route(6,l6_recover)])
save('blocked_06.json',[dict(level=6,name='L6 visiting both ends at different times does not latch L',max_frames=5000,phases=l6_recover[:2],scenario=dict(completed=False,deaths=0,box_resets=0,gates={'L':False,'R':False}))])

l7_other=[
    phase('Water chooses the first sightseeing ride',[go(5,19),go(17,19)],[go(10,19),go(7,19)]),
    phase('Fire keeps A powered while water opens B',[],[board(0),ride(370),jump(14,10),go(15,10),interact()]),
    phase('Meet on the balcony from different lifts',[go(35,19),board(1),ride(370),jump(33,10),go(18,10),go(20,10),jump(22,7,rise_first=True),go(28,10)],[go(30,10),go(28,10),jump(25,7,rise_first=True),go(28,10)]),
    phase('Return to the dry promenade',[go(41,19)],[go(43,19)]),
    phase('Finish side by side',[go(42,19)],[go(44,19)])]
save('alternate_07.json',[route(7,l7_other)])
l7_recover=[l7[0],
    phase('The first lift pauses when the keeper leaves',[dict(kind='input',direction=1,jump=True,frames=40),wait(120)],[wait(60),go(19,19),wait(120)]),
    phase('Step back onto A to resume the interrupted ride',[go(7,19),board(0),ride(370),jump(14,10),go(15,10),interact()],[go(17,19)]),
    *l7[2:]]
save('recovery_07.json',[route(7,l7_recover)])
save('main_path_07.json',[dict(level=7,name='L7 short dry promenade without the optional lift trip',phases=[phase('Walk directly to the exits',[go(42,19)],[go(44,19)])],scenario=dict(completed=True,deaths=0,box_resets=0))])

l5_other=[*l5[:2],
    phase('Scout steps onto the landing before unloading cargo',[ride(626),jump(21,18),go(22,18),interact()],[go(32,25)]),
    phase('Return to the still-powered freight lift for its cargo',[go(19,18),board(0),ride(666),push(18),jump(21,18)]),
    phase('Cargo now powers B; C was enabled first',[go(24,18)]),
    *l5[4:]]
save('alternate_05.json',[route(5,l5_other)])
l5_recover=[*l5[:2],
    phase('Keeper releases A midway; rider and cargo remain safe',[wait(180)],[go(32,25),wait(70),go(30,25),wait(90)]),
    phase('Return to A and finish unloading',[ride(666),push(18),jump(21,18)],[go(32,25)]),
    *l5[3:]]
save('recovery_05.json',[route(5,l5_recover)])
save('paused_05.json',[dict(level=5,name='L5 early A release safely suspends both rider and cargo',max_frames=5000,phases=l5_recover[:3],scenario=dict(completed=False,deaths=0,box_resets=0,fire_y_min=670,fire_y_max=735,box_y_min=670,box_y_max=735))])

# This route starts with the preserved returning-lift obstruction setup. After
# clearing it, wait outside the shaft for the next loading pass, then finish.
clear = json.loads((HERE/'clear_underside_05.json').read_text())[0]
l5_under = clear['phases'] + [
    phase('Wait outside, reload on the next pass, and unload upstairs',
          [wait(120),push(17),jump(12,25),board(0),ride(666),push(18),jump(21,18)]),
    phase('Keep C enabled and return to the summit route',[go(24,18)]),
    *l5[4:]]
save('underside_recovery_05.json',[route(5,l5_under)])

extends Control
## ==========================================================================
## RADAR MULTIBALL - Top Gun Pinball
## ==========================================================================
## This script → MPF: Posts events (radar_activate_mig_xxx, etc.)
## MPF → This script: Posts events (multiball_mig_hit_xxx, etc.)
## ==========================================================================

const MIG_DEFS := {
  "left_orbit": {"clock_deg":277.5,"difficulty":"easy","time_to_center":30.0,"label":"LO","full_name":"LEFT ORBIT",
    "mpf_hit_event":"multiball_mig_hit_left_orbit","mpf_activate_event":"radar_activate_mig_left_orbit","mpf_deactivate_event":"radar_deactivate_mig_left_orbit"},
  "left_ramp": {"clock_deg":315.0,"difficulty":"easy","time_to_center":30.0,"label":"LR","full_name":"LEFT RAMP",
    "mpf_hit_event":"multiball_mig_hit_left_ramp","mpf_activate_event":"radar_activate_mig_left_ramp","mpf_deactivate_event":"radar_deactivate_mig_left_ramp"},
  "spinner": {"clock_deg":337.5,"difficulty":"easy","time_to_center":30.0,"label":"SP","full_name":"SPINNER",
    "mpf_hit_event":"multiball_mig_hit_spinner","mpf_activate_event":"radar_activate_mig_spinner","mpf_deactivate_event":"radar_deactivate_mig_spinner"},
  "barrier": {"clock_deg":0.0,"difficulty":"easy","time_to_center":25.0,"label":"CNT","full_name":"BARRIER",
    "mpf_hit_event":"multiball_mig_hit_barrier","mpf_activate_event":"radar_activate_mig_barrier","mpf_deactivate_event":"radar_deactivate_mig_barrier"},
  "tower": {"clock_deg":15.0,"difficulty":"medium","time_to_center":60.0,"label":"TWR","full_name":"TOWER RAMP",
    "mpf_hit_event":"multiball_mig_hit_tower","mpf_activate_event":"radar_activate_mig_tower","mpf_deactivate_event":"radar_deactivate_mig_tower"},
  "top_orbit": {"clock_deg":30.0,"difficulty":"hard","time_to_center":75.0,"label":"TO","full_name":"TOP ORBIT",
    "mpf_hit_event":"multiball_mig_hit_top_orbit","mpf_activate_event":"radar_activate_mig_top_orbit","mpf_deactivate_event":"radar_deactivate_mig_top_orbit"},
  "top_ramp": {"clock_deg":45.0,"difficulty":"hard","time_to_center":75.0,"label":"TR","full_name":"TOP RAMP",
    "mpf_hit_event":"multiball_mig_hit_top_ramp","mpf_activate_event":"radar_activate_mig_top_ramp","mpf_deactivate_event":"radar_deactivate_mig_top_ramp"},
  "right_ramp": {"clock_deg":67.5,"difficulty":"easy","time_to_center":30.0,"label":"RR","full_name":"RIGHT RAMP",
    "mpf_hit_event":"multiball_mig_hit_right_ramp","mpf_activate_event":"radar_activate_mig_right_ramp","mpf_deactivate_event":"radar_deactivate_mig_right_ramp"},
}
const EVASION_SHOTS := ["left_orbit","left_ramp","spinner","barrier","tower","top_ramp","right_ramp"]
const SCORE_TIERS := {"easy":[500000,100000],"medium":[750000,150000],"hard":[1000000,200000],"super_hard":[1250000,250000]}
const WAVE_CFG := [[1.0,1.0,5],[1.15,1.15,10],[1.25,1.25,20],[1.5,1.5,40],[1.75,1.75,80],[2.0,2.0,160]]
const SWEEP_SPEED := 1.05
const TRAIL_ARC := 1.2
const TRAIL_SEGS := 60
const MIG_BR := 10.0
const MIG_MR := 18.0
const SD := 0.88
const CT := 0.055
const LT := 15.0
const SPT := 3.0
const PENALTY_DEFS := [
  {"id":"no_hold","name":"NO HOLD FLIPPERS","dur":20.0,"se":"radar_penalty_no_hold","ee":"radar_penalty_no_hold_ended"},
  {"id":"reversed","name":"REVERSED FLIPPERS","dur":20.0,"se":"radar_penalty_reversed","ee":"radar_penalty_reversed_ended"},
  {"id":"gi_off","name":"GI LIGHTS OFF","dur":20.0,"se":"radar_penalty_gi_off","ee":"radar_penalty_gi_off_ended"},
  {"id":"scoring_10","name":"SCORING AT 10%","dur":20.0,"se":"radar_penalty_scoring_reduced","ee":"radar_penalty_scoring_reduced_ended"},
  {"id":"progress_reset","name":"MIG PROGRESS RESET","dur":0.0,"se":"radar_penalty_progress_reset","ee":""},
]

var rc := Vector2.ZERO
var rr := 0.0
var sw := 0.0
var ms := {}
enum GS { PLAY, LOCKON, SPLASH }
var gs: int = GS.PLAY
var lkT := 0.0
var lkId := ""
var evId := ""
var spT := 0.0
var lastPen := ""
var wav := 1
var kwav := 0
var ktot := 0
var supLit := false
var supBank := 0
var pens := []
var scMult := 1.0
var df: Font

func _wc() -> Array: return WAVE_CFG[min(wav-1, WAVE_CFG.size()-1)]
func _ws() -> float: return _wc()[0]
func _wsc() -> float: return _wc()[1]
func _wsn() -> int: return int(_wc()[2])

func _mscore(id: String) -> int:
  var st = ms[id]; var t = SCORE_TIERS.get(st["d"], SCORE_TIERS["easy"])
  var p = clamp((st["dist"]-CT)/(SD-CT),0.0,1.0)
  return int((t[1]+(t[0]-t[1])*p)*_wsc()*scMult)

func _fmts(v: int) -> String:
  if v>=1000000: return "%.1fM" % (v/1000000.0)
  if v>=1000: return "%dK" % (v/1000)
  return str(v)

func _ready() -> void:
  rr = min(size.x,size.y)*0.46; rc = Vector2(size.x*0.42,size.y*0.44)
  df = ThemeDB.fallback_font
  for id in MIG_DEFS:
    var d = MIG_DEFS[id]
    ms[id] = {"on":false,"dist":SD,"br":0.0,"rad":deg_to_rad(d["clock_deg"]),"spd":SD/d["time_to_center"],"d":d["difficulty"]}
  randomize(); _spawn_init()
  # GMC EVENT CONNECTIONS - register with MPF BCP server
  for id in MIG_DEFS: MPF.server.add_event_handler(MIG_DEFS[id]["mpf_hit_event"], _on_shot.bind(id))
  MPF.server.add_event_handler("radar_evasion_hit", _on_evade)
  MPF.server.add_event_handler("multiball_ending", _on_ending)
  MPF.server.add_event_handler("radar_super_jackpot_hit", _on_super)

func _exit_tree() -> void:
  for id in MIG_DEFS: MPF.server.remove_event_handler(MIG_DEFS[id]["mpf_hit_event"], _on_shot.bind(id))
  MPF.server.remove_event_handler("radar_evasion_hit", _on_evade)
  MPF.server.remove_event_handler("multiball_ending", _on_ending)
  MPF.server.remove_event_handler("radar_super_jackpot_hit", _on_super)

func _process(delta: float) -> void:
  sw += SWEEP_SPEED*delta; if sw>=TAU: sw-=TAU
  for id in ms:
    if not ms[id]["on"]: continue
    var d = sw-ms[id]["rad"]; if d<0: d+=TAU
    var n = d/TAU; ms[id]["br"] = 1.0-(n/0.5)*0.85 if n<0.5 else 0.15
  for i in range(pens.size()-1,-1,-1):
    if pens[i]["t"]>0:
      pens[i]["t"]-=delta
      if pens[i]["t"]<=0:
        if pens[i]["ee"]!="": _ev(pens[i]["ee"])
        pens.remove_at(i)
  scMult = 0.1 if _hpen("scoring_10") else 1.0
  match gs:
    GS.PLAY: _umigs(delta)
    GS.LOCKON: lkT-=delta; if lkT<=0: _efail()
    GS.SPLASH: spT-=delta; if spT<=0: gs=GS.PLAY; _srm()
  queue_redraw()

func _draw() -> void:
  # Background
  draw_rect(Rect2(Vector2.ZERO,size),Color(0,0.02,0,1))
  draw_circle(rc,rr*1.01,Color(0,0.14,0,1))
  # Grid
  var gc = Color(0,0.35,0,0.25)
  draw_line(rc+Vector2(0,-rr),rc+Vector2(0,rr),gc,0.8)
  draw_line(rc+Vector2(-rr,0),rc+Vector2(rr,0),gc,0.8)
  for a in [45.0,135.0,225.0,315.0]:
    var o = Vector2(cos(deg_to_rad(a)),sin(deg_to_rad(a)))*rr
    draw_line(rc-o,rc+o,Color(0,0.28,0,0.12),0.5)
  # Rings
  for i in range(1,5): draw_arc(rc,rr*i/4.0,0,TAU,64,Color(0,0.4,0,0.28),0.7)
  # Ticks
  for d in range(0,360,5):
    var a = deg_to_rad(d)-PI/2; var m = d%10==0
    draw_line(rc+Vector2(cos(a),sin(a))*rr*(0.93 if m else 0.97),rc+Vector2(cos(a),sin(a))*rr,
      Color(0,0.45,0,0.45 if m else 0.18),1.0 if m else 0.4)
  # Sweep
  var sa = sw-PI/2
  for i in range(TRAIL_SEGS):
    var t = float(i)/TRAIL_SEGS; var al = pow(1.0-t,2.5)*0.4
    var a0=sa-TRAIL_ARC*t; var a1=sa-TRAIL_ARC*(t+1.0/TRAIL_SEGS)
    draw_polygon([rc,rc+Vector2(cos(a0),sin(a0))*rr,rc+Vector2(cos(a1),sin(a1))*rr],
      [Color(0,1,0,al),Color(0,1,0,al),Color(0,1,0,al)])
  draw_line(rc,rc+Vector2(cos(sa),sin(sa))*rr,Color(0,1,0,0.7),2)
  # MIGs
  for id in ms:
    if not ms[id]["on"]: continue
    var p = _mp(id); var dn = ms[id]["dist"]/SD; var br = ms[id]["br"]
    var bR = lerp(MIG_MR,MIG_BR,dn)
    draw_circle(p,bR*2,Color(0.15,1,0.15,br*0.25))
    draw_circle(p,bR,Color(0.25,0.9,0.25,br))
    draw_circle(p,bR*0.3,Color(1,1,1,br*0.5))
    if br>0.1:
      var sv = _mscore(id)
      draw_string(df,p+Vector2(-12,bR+14),MIG_DEFS[id]["label"],HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color(0.3,0.8,0.3,max(br,0.35)))
      draw_string(df,p+Vector2(-16,bR+25),_fmts(sv),HORIZONTAL_ALIGNMENT_LEFT,-1,9,Color(0.5,1,0.3,max(br,0.3)))
  draw_circle(rc,3,Color(0,0.8,0,0.8))
  # Vignette
  for i in range(20): draw_arc(rc,rr+float(i)*3,0,TAU,64,Color(0,0,0,float(i)/20*0.75),4)
  # HUD
  var ty = rc.y+rr+30; var ml = max(0,_wsn()-kwav)
  if not supLit:
    draw_string(df,Vector2(rc.x-rr*0.85,ty),"SHOOT DOWN %d MIGS TO LITE SUPER JACKPOT"%ml,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(0.35,0.7,0.15,0.55))
  else:
    var fl = abs(sin(Time.get_ticks_msec()*0.006))
    draw_string(df,Vector2(rc.x-rr*0.55,ty),">>> SUPER JACKPOT LIT <<<",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color(1,1,0,0.5+fl*0.5))
  draw_string(df,Vector2(rc.x-rr*0.5,ty+18),"SUPER BANK: %s"%_fmts(supBank),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color(1,1,0,0.6))
  draw_string(df,Vector2(rc.x-rr*0.5,ty+34),"WAVE %d | MIGS: %d/%d"%[wav,kwav,_wsn()],HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color(0.4,0.65,0.25,0.6))
  # Overlays
  if gs==GS.LOCKON: _dlockon()
  if gs==GS.SPLASH: _dsplash()
  # Penalties
  if pens.size()>0 and gs==GS.PLAY:
    var fl = abs(sin(Time.get_ticks_msec()*0.005)); var py = rc.y+rr+55
    for pen in pens:
      if pen["t"]<=0: continue
      draw_string(df,Vector2(rc.x-rr*0.5,py),"⚠ %s: %ds ⚠"%[pen["n"],int(ceil(pen["t"]))],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color(1,0.15,0.1,0.4+fl*0.5))
      py+=18

func _dlockon() -> void:
  draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,0.55))
  var fl = abs(sin(lkT*3)); var bc = Color(1,0.25,0,0.4+fl*0.5)
  for r in [Rect2(0,0,size.x,6),Rect2(0,size.y-6,size.x,6),Rect2(0,0,6,size.y),Rect2(size.x-6,0,6,size.y)]: draw_rect(r,bc)
  draw_string(df,Vector2(size.x*0.15,size.y*0.32),"⚠  MIG LOCKING ON  ⚠",HORIZONTAL_ALIGNMENT_LEFT,-1,36,Color(1,0.2,0,0.65+fl*0.35))
  draw_string(df,Vector2(size.x*0.42,size.y*0.52),"%d"%int(ceil(lkT)),HORIZONTAL_ALIGNMENT_LEFT,-1,60,Color(1,0.8,0,0.9) if lkT>5 else Color(1,0.1,0,0.6+fl*0.4))
  var bx=size.x*0.15; var by=size.y*0.57; var bw=size.x*0.7; var pc=lkT/LT
  draw_rect(Rect2(bx,by,bw,12),Color(0.12,0.12,0.12,0.7))
  draw_rect(Rect2(bx,by,bw*pc,12),Color(0,0.8,0,0.85) if pc>0.3 else Color(1,0,0,0.5+fl*0.5))
  if evId!="" and evId in MIG_DEFS:
    var ef = abs(sin(lkT*5))
    draw_string(df,Vector2(size.x*0.15,size.y*0.76),"HIT  %s  TO EVADE!"%MIG_DEFS[evId]["full_name"],HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color(0,1,0,0.4+ef*0.6))

func _dsplash() -> void:
  var fl = abs(sin(spT*4))
  draw_rect(Rect2(Vector2.ZERO,size),Color(0.3,0,0,0.35+fl*0.2))
  for r in [Rect2(0,0,size.x,8),Rect2(0,size.y-8,size.x,8),Rect2(0,0,8,size.y),Rect2(size.x-8,0,8,size.y)]: draw_rect(r,Color(1,0,0,0.5+fl*0.4))
  draw_string(df,Vector2(size.x*0.18,size.y*0.38),"YOU'VE BEEN HIT!",HORIZONTAL_ALIGNMENT_LEFT,-1,44,Color(1,0.1,0,0.7+fl*0.3))
  draw_string(df,Vector2(size.x*0.2,size.y*0.56),"PENALTY: %s"%lastPen,HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color(1,0.55,0.15,0.6+fl*0.4))

func _umigs(dt: float) -> void:
  for id in ms:
    if not ms[id]["on"]: continue
    ms[id]["dist"]-=ms[id]["spd"]*_ws()*dt
    if ms[id]["dist"]<=CT: _slk(id); return

func _spawn_init() -> void:
  var h=[]; var m=[]; var e=[]
  for id in MIG_DEFS:
    match MIG_DEFS[id]["difficulty"]:
      "hard": h.append(id)
      "medium": m.append(id)
      "easy": e.append(id)
  h.shuffle(); m.shuffle(); e.shuffle()
  if h.size()>0: _am(h[0])
  if m.size()>0: _am(m[0])
  for i in range(min(2,e.size())): _am(e[i])

func _am(id: String) -> void:
  ms[id]["on"]=true; ms[id]["dist"]=SD; ms[id]["br"]=0.0
  _ev(MIG_DEFS[id]["mpf_activate_event"])

func _dm(id: String) -> void:
  ms[id]["on"]=false; ms[id]["dist"]=SD
  _ev(MIG_DEFS[id]["mpf_deactivate_event"])

func _srm() -> void:
  var av=[]; for id in ms: if not ms[id]["on"]: av.append(id)
  if av.size()>0: av.shuffle(); _am(av[0])

func _destroy(id: String) -> void:
  if id not in ms or not ms[id]["on"]: return
  var sc = _mscore(id); _dm(id)
  ktot+=1; kwav+=1; supBank+=sc
  _ev("radar_mig_destroyed")
  if kwav>=_wsn() and not supLit: supLit=true; _ev("radar_super_jackpot_lit")
  call_deferred("_srm")

func _slk(id: String) -> void:
  gs=GS.LOCKON; lkT=LT; lkId=id; ms[id]["dist"]=CT
  var av=[]; for s in EVASION_SHOTS: if s!=id: av.append(s)
  av.shuffle(); evId=av[0] if av.size()>0 else "spinner"
  _ev("radar_mig_lockon"); _ev("radar_evasion_shot_"+evId)

func _on_evade(_msg = null) -> void:
  if gs!=GS.LOCKON: return
  _dm(lkId); gs=GS.PLAY; lkId=""; evId=""
  _ev("radar_evasion_success"); call_deferred("_srm")

func _efail() -> void:
  _dm(lkId); lkId=""; evId=""
  var pd = PENALTY_DEFS[randi()%PENALTY_DEFS.size()]
  lastPen=pd["name"]
  if pd["id"]=="progress_reset": kwav=0; _ev(pd["se"])
  else: pens.append({"id":pd["id"],"n":pd["name"],"t":pd["dur"],"ee":pd["ee"]}); _ev(pd["se"])
  gs=GS.SPLASH; spT=SPT; _ev("radar_evasion_failed"); _ev("radar_punishment_start")

func _on_super(_msg = null) -> void:
  supLit=false; _ev("radar_super_jackpot_collected")
  wav+=1; kwav=0; supBank=0; _ev("radar_wave_advance")

func _hpen(pid: String) -> bool:
  for p in pens: if p["id"]==pid and p["t"]>0: return true
  return false

func _on_shot(_msg, id: String) -> void:
  if _hpen("scoring_10"):
    if id in ms and ms[id]["on"]: _dm(id); _ev("radar_mig_destroyed_no_score"); call_deferred("_srm")
    return
  _destroy(id)

func _on_ending(_msg = null) -> void:
  for id in ms: if ms[id]["on"]: _dm(id)
  gs=GS.PLAY; pens.clear()

func _mp(id: String) -> Vector2:
  var a = ms[id]["rad"]-PI/2; return rc+Vector2(cos(a),sin(a))*ms[id]["dist"]*rr

func _ev(e: String) -> void:
  MPF.server.send_event(e)

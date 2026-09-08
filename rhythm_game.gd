extends Node2D

const LANES := 6
const SONG_LENGTH := 54.0
const APPROACH_TIME := 1.65
const PERFECT := 0.055
const GREAT := 0.105
const GOOD := 0.165
const HIT_Y_RATIO := 0.795
const COLORS := [Color("ff5f91"), Color("bd72ff"), Color("5caeff"), Color("55e4e0"), Color("74f59a"), Color("ffe36e")]
const TYPE_TAP := 0
const TYPE_HOLD := 1
const TYPE_FLICK := 2

# Optional feature module. Set this to false (or remove the clearly marked block
# below) to restore the original scoring/life behaviour without touching gameplay.
const FEATURE_STREAK_REWARDS := true
const STREAK_STEP := 25
const STREAK_SCORE_BONUS := 2500
const STREAK_LIFE_RECOVERY := 4.0

var song_time := -2.8
var playing := false
var finished := false
var notes: Array[Dictionary] = []
var held_lanes := {}
var score := 0
var combo := 0
var max_combo := 0
var life := 100.0
var perfect_count := 0
var great_count := 0
var good_count := 0
var miss_count := 0
var judgement := "READY?"
var judgement_age := 0.0
var pulse := 0.0
var particles: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var font: Font
var audio: AudioStreamPlayer
var track: AudioStreamGenerator
var sample_pos := 0.0
var config_open := false
var config_selected := -1
var paused := false
var course_select_open := true
var course_index := 0
var courses: Array[Dictionary] = []
var course_length := SONG_LENGTH
var streak_bonus_text := ""
var streak_bonus_age := 99.0

func _ready() -> void:
	rng.seed = 745231
	font = ThemeDB.fallback_font
	load_keybinds()
	build_courses()
	setup_audio()
	queue_redraw()

func setup_audio() -> void:
	audio = AudioStreamPlayer.new()
	track = AudioStreamGenerator.new()
	track.mix_rate = 44100
	track.buffer_length = 0.25
	audio.stream = track
	audio.volume_db = -11.0
	add_child(audio)

func build_courses() -> void:
	var names := ["First Light", "Pastel Steps", "City Pop Spark", "Blue Horizon", "Sugar Rush", "Midnight Train", "Prism Parade", "Afterimage", "Candy Circuit", "Glow Garden", "Starry Signal", "Voltage Bloom", "Cloud Chaser", "Neon Skies", "Satellite Heart", "Mirror Beat", "Laser Lagoon", "Comet Drive", "Moonlit Rush", "Chromatic Run", "Digital Dancer", "Aurora Storm", "Skyline Fever", "Starlight Riot", "Hyper Bloom", "Cosmic Sprint", "Rainbow Reactor", "Final Frequency", "Infinity Stage", "Neon Finale"]
	for i in range(30):
		courses.append({"name": names[i], "bpm": 96 + i * 3, "level": 1 + int(i / 3), "steps": 68 + i * 6})

func start_course(index: int) -> void:
	course_index = clampi(index, 0, courses.size() - 1)
	notes.clear(); held_lanes.clear(); particles.clear()
	score = 0; combo = 0; max_combo = 0; life = 100.0
	streak_bonus_text = ""; streak_bonus_age = 99.0
	perfect_count = 0; great_count = 0; good_count = 0; miss_count = 0
	sample_pos = 0.0; song_time = -2.8; playing = false; finished = false; paused = false
	build_chart_for_course(courses[course_index])

func build_chart_for_course(course: Dictionary) -> void:
	var beat: float = 60.0 / float(course.bpm)
	var difficulty: int = int(course.level)
	var t := 1.7
	var steps: int = int(course.steps)
	# Density rises from accessible quarter-beat patterns to rapid, layered six-lane charts.
	for i in range(steps):
		var lane := (i * (2 + difficulty % 3) + course_index * 3 + int(i / 11)) % LANES
		var kind := TYPE_TAP
		var duration := 0.0
		if difficulty >= 4 and i % max(8, 18-difficulty) == 0:
			kind = TYPE_HOLD; duration = beat * (1.2 + difficulty * .09)
		elif difficulty >= 3 and i % max(7, 15-difficulty) == 3:
			kind = TYPE_FLICK
		add_note(t, lane, kind, duration)
		if difficulty >= 2 and i % max(10, 22-difficulty*2) == 5:
			add_note(t, (lane + 2 + difficulty) % LANES, TYPE_TAP)
		if difficulty >= 7 and i % 13 == 7:
			add_note(t, (lane + 3) % LANES, TYPE_FLICK)
		var subdivision := 1.0 if difficulty <= 2 else (.75 if difficulty <= 5 else .5)
		t += beat * subdivision
	course_length = t + 2.0

func add_note(time: float, lane: int, kind: int, duration := 0.0) -> void:
	notes.append({"time": time, "lane": lane, "type": kind, "duration": duration, "hit": false, "holding": false, "released": false})

func _process(delta: float) -> void:
	if course_select_open or paused:
		queue_redraw()
		return
	if not playing and not finished:
		song_time += delta
		if song_time >= 0.0:
			playing = true; audio.play(); judgement = "START!"; judgement_age = 0.0
	elif playing:
		song_time += delta; fill_audio(); process_misses()
		if song_time > course_length or all_notes_done():
			playing = false; finished = true; audio.stop(); judgement = "LIVE CLEAR!" if life > 0 else "LIVE FAILED"; judgement_age = 0.0
	judgement_age += delta
	streak_bonus_age += delta
	pulse = maxf(0.0, pulse - delta * 2.8)
	update_particles(delta)
	queue_redraw()

func fill_audio() -> void:
	if not audio.playing: return
	var playback: AudioStreamGeneratorPlayback = audio.get_stream_playback()
	if playback == null: return
	for i in range(playback.get_frames_available()):
		var time := sample_pos / track.mix_rate
		var bass := sin(TAU * 64.0 * time) * (0.22 if fmod(time, 0.46875) < 0.09 else 0.0)
		var chord := (sin(TAU * 261.63 * time) + sin(TAU * 329.63 * time) + sin(TAU * 392.0 * time)) * 0.045
		var arp := sin(TAU * (523.25 + 110.0 * sin(TAU * 0.25 * time)) * time) * 0.055
		playback.push_frame(Vector2.ONE * (bass + chord + arp)); sample_pos += 1.0

func process_misses() -> void:
	for n in notes:
		if not n.hit and song_time - n.time > GOOD:
			n.hit = true; n.released = true; register_judgement("MISS")
		if n.holding and song_time >= n.time + n.duration:
			n.holding = false; n.released = true; held_lanes.erase(n.lane); register_judgement("PERFECT")

func all_notes_done() -> bool:
	for n in notes:
		if not n.released: return false
	return song_time > 4.0

func _input(event: InputEvent) -> void:
	if course_select_open:
		handle_course_select_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and not config_open:
		paused = not paused
		if audio.playing: audio.stream_paused = paused
		queue_redraw()
		return
	if paused: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		config_open = not config_open
		config_selected = -1
		queue_redraw()
		return
	if config_open:
		handle_config_input(event)
		return
	if finished:
		if event.is_pressed(): get_tree().reload_current_scene()
		return
	if not playing: return
	if event is InputEventKey:
		for lane in range(LANES):
			var action := "lane_%d" % lane
			if InputMap.event_is_action(event, action):
				if event.pressed and not event.echo: hit_lane(lane)
				elif not event.pressed: release_lane(lane)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var lane := lane_from_x(event.position.x)
		if lane >= 0: hit_lane(lane)
	if event is InputEventScreenTouch and event.pressed:
		var lane := lane_from_x(event.position.x)
		if lane >= 0: hit_lane(lane)

func lane_from_x(x: float) -> int:
	var r := play_rect()
	if x < r.position.x or x > r.end.x: return -1
	return clampi(int((x-r.position.x)/(r.size.x/LANES)),0,LANES-1)

func load_keybinds() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://keybinds.cfg") != OK: return
	for lane in range(LANES):
		var code := int(cfg.get_value("keys", "lane_%d" % lane, 0))
		if code == 0: continue
		var key_event := InputEventKey.new()
		key_event.physical_keycode = code
		InputMap.action_erase_events("lane_%d" % lane)
		InputMap.action_add_event("lane_%d" % lane, key_event)

func save_keybinds() -> void:
	var cfg := ConfigFile.new()
	for lane in range(LANES):
		var events := InputMap.action_get_events("lane_%d" % lane)
		if not events.is_empty() and events[0] is InputEventKey:
			cfg.set_value("keys", "lane_%d" % lane, (events[0] as InputEventKey).physical_keycode)
	cfg.save("user://keybinds.cfg")

func key_label(lane: int) -> String:
	var events := InputMap.action_get_events("lane_%d" % lane)
	if events.is_empty() or not events[0] is InputEventKey: return "—"
	return OS.get_keycode_string((events[0] as InputEventKey).physical_keycode)

func handle_config_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var s := get_viewport_rect().size
		var panel := Rect2(s.x*.5-250,s.y*.5-210,500,420)
		for lane in range(LANES):
			var row := Rect2(panel.position.x+45,panel.position.y+92+lane*42,410,34)
			if row.has_point(event.position):
				config_selected = lane
				queue_redraw()
				return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			config_selected = -1
			queue_redraw()
			return
		if config_selected >= 0 and event.keycode != KEY_TAB:
			var replacement := InputEventKey.new()
			replacement.physical_keycode = event.physical_keycode
			InputMap.action_erase_events("lane_%d" % config_selected)
			InputMap.action_add_event("lane_%d" % config_selected, replacement)
			save_keybinds()
			config_selected = -1
			queue_redraw()

func handle_course_select_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_RIGHT, KEY_DOWN]: course_index = (course_index + 1) % courses.size()
		elif event.keycode in [KEY_LEFT, KEY_UP]: course_index = (course_index - 1 + courses.size()) % courses.size()
		elif event.keycode in [KEY_ENTER, KEY_SPACE]:
			course_select_open = false
			start_course(course_index)
		queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var s := get_viewport_rect().size
		var panel := Rect2(s.x*.5-410,115,820,s.y-190)
		for visible in range(10):
			var index := int(course_index / 10) * 10 + visible
			if index >= courses.size(): continue
			var col := visible % 2; var row := int(visible / 2)
			var card := Rect2(panel.position.x+20+col*390,panel.position.y+80+row*75,370,60)
			if card.has_point(event.position):
				if index == course_index:
					course_select_open = false; start_course(course_index)
				else: course_index = index
				queue_redraw()
				return

func hit_lane(lane: int) -> void:
	var best: Dictionary = {}; var best_delta := 999.0
	for n in notes:
		if n.lane != lane or n.hit: continue
		var d := absf(song_time-n.time)
		if d < best_delta: best=n; best_delta=d
	if best.is_empty() or best_delta > GOOD: register_judgement("MISS"); return
	var result := "GOOD"
	if best_delta <= PERFECT: result="PERFECT"
	elif best_delta <= GREAT: result="GREAT"
	best.hit=true
	if best.type == TYPE_HOLD: best.holding=true; held_lanes[lane]=best
	else: best.released=true
	register_judgement(result); spawn_burst(lane,COLORS[lane])

func release_lane(lane: int) -> void:
	if not held_lanes.has(lane): return
	var n: Dictionary=held_lanes[lane]
	n.holding=false; n.released=true; held_lanes.erase(lane)
	if song_time < n.time+n.duration-GOOD: register_judgement("MISS")

func register_judgement(result: String) -> void:
	judgement=result; judgement_age=0.0; pulse=1.0
	if result == "PERFECT": perfect_count+=1; combo+=1; score+=1000; life=minf(100,life+.25)
	elif result == "GREAT": great_count+=1; combo+=1; score+=700; life=minf(100,life+.1)
	elif result == "GOOD": good_count+=1; combo+=1; score+=400
	else: miss_count+=1; combo=0; life=maxf(0,life-5.5)
	max_combo=maxi(max_combo,combo)
	apply_streak_reward()

# --- OPTIONAL FEATURE: STREAK REWARDS (safe to remove as one unit) ---
func apply_streak_reward() -> void:
	if not FEATURE_STREAK_REWARDS or combo == 0 or combo % STREAK_STEP != 0: return
	score += STREAK_SCORE_BONUS
	life = minf(100.0, life + STREAK_LIFE_RECOVERY)
	streak_bonus_text = "STREAK BONUS  +%d" % STREAK_SCORE_BONUS
	streak_bonus_age = 0.0
	pulse = 1.0
# --- END OPTIONAL FEATURE ---

func play_rect() -> Rect2:
	var s:=get_viewport_rect().size; var w:=minf(s.x*.56,620.0)
	return Rect2((s.x-w)*.5,88,w,s.y-156)

func spawn_burst(lane: int,color: Color) -> void:
	var r:=play_rect(); var x:=r.position.x+(lane+.5)*r.size.x/LANES; var y:=r.position.y+r.size.y*HIT_Y_RATIO
	for i in range(14): particles.append({"p":Vector2(x,y),"v":Vector2(rng.randf_range(-210,210),rng.randf_range(-230,30)),"life":rng.randf_range(.32,.72),"max":.72,"c":color})

func update_particles(delta: float) -> void:
	for p in particles: p.p+=p.v*delta; p.v.y+=500*delta; p.life-=delta
	particles=particles.filter(func(p): return p.life>0)

func _draw() -> void:
	var s:=get_viewport_rect().size; draw_background(s)
	if course_select_open: draw_course_select(s); return
	if finished: draw_results(s); return
	draw_stage(s); draw_hud(s)
	if config_open: draw_key_config(s)
	if paused: draw_pause(s)

func draw_background(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO,s),Color("070817"))
	for i in range(14):
		var y:=fmod(float(i)*79.0+song_time*(18+i%3*9),s.y+140)-70
		draw_line(Vector2(0,y),Vector2(s.x,y+100),Color(0.1,0.08,0.3,0.32),1)
	var c:=Vector2(s.x*.5,s.y*.36)
	for r in [380,280,180]: draw_arc(c,r+pulse*10,0,TAU,48,Color(0.2,0.75,1,0.045),2)

func draw_stage(s: Vector2) -> void:
	var r:=play_rect()
	draw_colored_polygon(PackedVector2Array([Vector2(r.position.x-55,r.position.y),Vector2(r.end.x+55,r.position.y),Vector2(r.end.x+10,r.end.y),Vector2(r.position.x-10,r.end.y)]),Color("101034"))
	for i in range(LANES+1):
		var x:=r.position.x+i*r.size.x/LANES; draw_line(Vector2(x,r.position.y),Vector2(x,r.end.y),Color(0.32,0.6,1,0.30),2)
	var hy:=r.position.y+r.size.y*HIT_Y_RATIO
	draw_rect(Rect2(r.position.x-12,hy-6,r.size.x+24,12),Color(0.6,0.95,1,0.16)); draw_line(Vector2(r.position.x-15,hy),Vector2(r.end.x+15,hy),Color("d8fbff"),2.5+pulse*2)
	for lane in range(LANES):
		var x:=r.position.x+lane*r.size.x/LANES; draw_rect(Rect2(x+5,hy+16,r.size.x/LANES-10,38),COLORS[lane].darkened(.3)); draw_string(font,Vector2(x+r.size.x/LANES*.5-18,hy+42),key_label(lane),HORIZONTAL_ALIGNMENT_CENTER,38,18,Color.WHITE)
	draw_notes(r,hy)
	for p in particles: draw_circle(p.p,3.5,Color(p.c,p.life/p.max))

func draw_notes(r: Rect2,hy: float) -> void:
	for n in notes:
		if n.released: continue
		var progress:float=(song_time-(n.time-APPROACH_TIME))/APPROACH_TIME
		if progress<-.1 or progress>1.3: continue
		var y: float=lerpf(r.position.y-38,hy,progress); var w: float=r.size.x/LANES; var x: float=r.position.x+n.lane*w+9; var c:Color=COLORS[n.lane]
		if n.type==TYPE_HOLD:
			var ey:=lerpf(r.position.y-38,hy,(song_time-(n.time+n.duration-APPROACH_TIME))/APPROACH_TIME); draw_rect(Rect2(x+w*.34,y,w*.32,ey-y),Color(c,.56))
		if n.type==TYPE_FLICK:
			draw_circle(Vector2(x+w*.5,y),23,c.darkened(.45)); draw_string(font,Vector2(x+w*.5-10,y+8),"↑",HORIZONTAL_ALIGNMENT_CENTER,20,26,Color.WHITE)
		else:
			draw_circle(Vector2(x+w*.5,y),21,c.darkened(.48)); draw_circle(Vector2(x+w*.5,y),16,c); draw_arc(Vector2(x+w*.5,y),16,0,TAU,24,Color.WHITE,1.4)

func draw_hud(s: Vector2) -> void:
	var course: Dictionary = courses[course_index]
	draw_string(font,Vector2(38,50),"NEON BEAT LIVE",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("d9efff")); draw_string(font,Vector2(40,77),"%02d  %s  ·  LV %d  ·  %d BPM" % [course_index+1,course.name,course.level,course.bpm],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("7084b8"))
	draw_string(font,Vector2(s.x-260,52),"SCORE  %07d"%score,HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color.WHITE); draw_rect(Rect2(s.x-260,67,205,8),Color("282b49")); draw_rect(Rect2(s.x-260,67,205*life/100.0,8),Color("66ffc8") if life>35 else Color("ff5f7b"))
	draw_string(font,Vector2(s.x*.5-80,112),str(combo),HORIZONTAL_ALIGNMENT_CENTER,160,52,Color.WHITE); draw_string(font,Vector2(s.x*.5-50,136),"COMBO",HORIZONTAL_ALIGNMENT_CENTER,100,14,Color("85a5d9"))
	if judgement_age<.65:
		var jc:=Color("fff4ad") if judgement=="PERFECT" else Color("cbefff")
		if judgement=="MISS": jc=Color("ff6e93")
		draw_string(font,Vector2(s.x*.5-110,s.y*.62),judgement,HORIZONTAL_ALIGNMENT_CENTER,220,32+pulse*7,jc)
	if streak_bonus_age < 1.15:
		var alpha := clampf(1.0-streak_bonus_age/1.15,0.0,1.0)
		draw_string(font,Vector2(s.x*.5-150,s.y*.62+33),streak_bonus_text,HORIZONTAL_ALIGNMENT_CENTER,300,16,Color(1.0,0.88,0.36,alpha))
	if song_time<0: draw_string(font,Vector2(s.x*.5-90,s.y*.5),"%.0f"%ceil(-song_time),HORIZONTAL_ALIGNMENT_CENTER,180,74,Color.WHITE)

func draw_results(s: Vector2) -> void:
	draw_rect(Rect2(s.x*.5-260,s.y*.5-220,520,440),Color("141735")); draw_rect(Rect2(s.x*.5-260,s.y*.5-220,520,4),Color("63ddff")); draw_string(font,Vector2(s.x*.5-180,s.y*.5-153),judgement,HORIZONTAL_ALIGNMENT_CENTER,360,36,Color("e9f9ff")); draw_string(font,Vector2(s.x*.5-180,s.y*.5-98),"%07d"%score,HORIZONTAL_ALIGNMENT_CENTER,360,54,Color("fff2a8")); draw_string(font,Vector2(s.x*.5-130,s.y*.5-45),"MAX COMBO  %d"%max_combo,HORIZONTAL_ALIGNMENT_CENTER,260,20,Color("a8c5ff"))
	var rows:=[["PERFECT",perfect_count,Color("fff1a8")],["GREAT",great_count,Color("9ce8ff")],["GOOD",good_count,Color("9fffc3")],["MISS",miss_count,Color("ff7d9a")]]
	for i in range(rows.size()):
		var row=rows[i]; draw_string(font,Vector2(s.x*.5-120,s.y*.5+10+i*32),row[0],HORIZONTAL_ALIGNMENT_LEFT,160,19,row[2]); draw_string(font,Vector2(s.x*.5+90,s.y*.5+10+i*32),str(row[1]),HORIZONTAL_ALIGNMENT_RIGHT,70,19,Color.WHITE)
	draw_string(font,Vector2(s.x*.5-190,s.y*.5+170),"PRESS ANY KEY / CLICK TO PLAY AGAIN",HORIZONTAL_ALIGNMENT_CENTER,380,15,Color("8292bf"))

func draw_pause(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO,s),Color(0.01,0.02,0.08,0.72))
	draw_string(font,Vector2(s.x*.5-180,s.y*.5-24),"PAUSED",HORIZONTAL_ALIGNMENT_CENTER,360,52,Color("effaff"))
	draw_string(font,Vector2(s.x*.5-180,s.y*.5+18),"PRESS ESC TO RESUME",HORIZONTAL_ALIGNMENT_CENTER,360,16,Color("9cbae8"))

func draw_course_select(s: Vector2) -> void:
	var panel := Rect2(s.x*.5-410,115,820,s.y-190)
	draw_rect(panel,Color("111530"))
	draw_rect(Rect2(panel.position,Vector2(panel.size.x,4)),Color("63ddff"))
	draw_string(font,panel.position+Vector2(26,42),"SELECT COURSE",HORIZONTAL_ALIGNMENT_LEFT,500,28,Color("eaf8ff"))
	draw_string(font,panel.position+Vector2(510,40),"%02d / 30" % [course_index+1],HORIZONTAL_ALIGNMENT_RIGHT,275,18,Color("8aa5d9"))
	var start := int(course_index / 10) * 10
	for visible in range(10):
		var index := start + visible
		if index >= courses.size(): continue
		var course: Dictionary = courses[index]
		var col := visible % 2; var row := int(visible / 2)
		var card := Rect2(panel.position.x+20+col*390,panel.position.y+80+row*75,370,60)
		var selected := index == course_index
		draw_rect(card,Color("29315b") if selected else Color("1b2142"))
		if selected: draw_rect(Rect2(card.position,Vector2(5,card.size.y)),COLORS[index%LANES])
		draw_string(font,card.position+Vector2(18,25),"%02d  %s" % [index+1,course.name],HORIZONTAL_ALIGNMENT_LEFT,285,18,Color.WHITE)
		draw_string(font,card.position+Vector2(18,47),"LV %02d   %d BPM   %d NOTES" % [course.level,course.bpm,int(course.steps)],HORIZONTAL_ALIGNMENT_LEFT,315,13,Color("a5b8e5"))
	draw_string(font,panel.position+Vector2(25,panel.size.y-25),"ARROW KEYS: SELECT    ENTER / CLICK AGAIN: START",HORIZONTAL_ALIGNMENT_LEFT,770,14,Color("91a5d2"))

func draw_key_config(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO,s),Color(0.01,0.02,0.08,0.72))
	var panel := Rect2(s.x*.5-250,s.y*.5-210,500,420)
	draw_rect(panel,Color("151936"))
	draw_rect(Rect2(panel.position,panel.size*Vector2(1,0.012)),Color("63ddff"))
	draw_string(font,panel.position+Vector2(45,50),"KEY CONFIG",HORIZONTAL_ALIGNMENT_LEFT,410,30,Color("ecf8ff"))
	draw_string(font,panel.position+Vector2(45,74),"Click a lane, then press its new key",HORIZONTAL_ALIGNMENT_LEFT,410,15,Color("99a9d4"))
	for lane in range(LANES):
		var row := Rect2(panel.position.x+45,panel.position.y+92+lane*42,410,34)
		var active := lane == config_selected
		draw_rect(row,COLORS[lane].darkened(.55) if active else Color("222848"))
		draw_rect(Rect2(row.position,Vector2(5,row.size.y)),COLORS[lane])
		draw_string(font,row.position+Vector2(18,23),"LANE %d" % (lane+1),HORIZONTAL_ALIGNMENT_LEFT,120,17,Color.WHITE)
		var text := "PRESS A KEY..." if active else key_label(lane)
		draw_string(font,row.position+Vector2(210,23),text,HORIZONTAL_ALIGNMENT_RIGHT,175,17,Color("fff0a2") if active else Color("c8e8ff"))
	draw_string(font,panel.position+Vector2(45,385),"TAB: CLOSE   ·   ESC: CANCEL SELECTION",HORIZONTAL_ALIGNMENT_LEFT,410,14,Color("8292bf"))

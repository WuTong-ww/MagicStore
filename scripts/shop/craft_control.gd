extends Control
## An unspent local operation. The sole durable boundary is Main.run_action.
const UI = preload("res://scripts/ui/ui_kit.gd")
const Config = preload("res://scripts/shop/craft_config.gd")
const Rules = preload("res://scripts/shop/craft_rules.gd")
const Surface = preload("res://scripts/shop/craft_surface.gd")
const Ingredient = preload("res://scripts/shop/craft_ingredient.gd")
var host: Node
var config: Dictionary = {}
var catalog: Dictionary = {}
var basis: Dictionary = {}
var draft: Dictionary = {}
var stage := "feeding"
var command_id := ""
var accumulator := 0.0
var fire_pressed := false
var pending := false
var shelf: VBoxContainer
var stage_label: Label
var selected_label: Label
var note: Label
var action_button: Button
var cancel_button: Button
var fire_button: Button
var reset_button: Button
var quantity_buttons: Array = []
var disk: Control
var mortar: Control
var fire: Control
var pointer_tween: Tween

func begin(owner_host: Node, target_id: String = "") -> bool:
	host = owner_host
	basis = GameState.snapshot()
	catalog = GameState.shop_view().get("catalog",{})
	config = Config.load_config(catalog)
	if config.is_empty() or basis.is_empty(): return false
	draft = {"protocol_version":config.version,"ruleset_id":config.ruleset_id,"save_id":basis.save_id,"base_version":basis.state_version,"mode":"experiment" if target_id.is_empty() else "known","target_id":target_id,"quantity":1,"ingredients":[],"grind_trace":[],"fire_trace":[]}
	command_id = GameState.make_id("craft")
	_build()
	set_process(true)
	return true

func _build() -> void:
	var copy: Dictionary = config.ui.copy
	var margin := UI.margin(int(config.ui.layout.padding))
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",int(config.ui.layout.gap))
	margin.add_child(box)
	box.add_child(UI.paper_heading(copy.title))
	var options := HBoxContainer.new()
	box.add_child(options)
	for quantity: int in range(int(config.limits.quantity_min),int(config.limits.quantity_max)+1):
		var button := UI.button(String(copy.quantity).format({"quantity":quantity}),func(): _quantity(quantity))
		button.toggle_mode = true
		options.add_child(button)
		quantity_buttons.append(button)
	var target: Dictionary = config.targets.get(draft.target_id,{})
	var per_minutes: int = int(target.get("minutes",config.experiment.minutes_per_portion))
	var per_energy: int = int(target.get("energy",config.experiment.energy_per_portion))
	var cost := UI.label(String(copy.cost).format({"minutes":per_minutes,"energy":per_energy}),int(config.ui.layout.minimum_font))
	cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost.custom_minimum_size.x = config.ui.layout.board_size
	options.add_child(cost)
	stage_label = UI.label(copy.loading,26)
	box.add_child(stage_label)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",int(config.ui.layout.gap))
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(columns)
	var scroll := ScrollContainer.new()
	scroll.name = "CraftMaterialShelf"
	scroll.custom_minimum_size.x = config.ui.layout.shelf_width
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(scroll)
	shelf = VBoxContainer.new()
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(shelf)
	var disk_box := VBoxContainer.new()
	columns.add_child(disk_box)
	var cool := UI.label(copy.cool,int(config.ui.layout.minimum_font))
	cool.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	disk_box.add_child(cool)
	disk = Surface.new()
	disk.name = "CraftPotency"
	disk.setup(config,"potency")
	var known: Array = basis.shop.recipes.duplicate()
	var inspired: Array = []
	for demand: Dictionary in basis.shop.demands.values():
		if not str(demand.get("recipe_id","")).is_empty(): inspired.append(demand.recipe_id)
	var projection := Rules.public_view(config,known,inspired)
	disk.targets = projection.known_targets.filter(func(row: Dictionary) -> bool: return draft.mode == "experiment" or row.target_id == draft.target_id)
	disk.hints = projection.hints
	disk_box.add_child(disk)
	var axes := HBoxContainer.new()
	disk_box.add_child(axes)
	var calm := UI.label(copy.calm,int(config.ui.layout.minimum_font))
	var alert := UI.label(copy.alert,int(config.ui.layout.minimum_font))
	calm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alert.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	axes.add_child(calm); axes.add_child(alert)
	var warm := UI.label(copy.warm,int(config.ui.layout.minimum_font))
	warm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	disk_box.add_child(warm)
	var work := VBoxContainer.new()
	columns.add_child(work)
	mortar = Surface.new()
	mortar.name = "CraftMortar"
	mortar.setup(config,"mortar")
	mortar.ingredient_dropped.connect(feed)
	work.add_child(mortar)
	fire = Surface.new()
	fire.name = "CraftTemperature"
	fire.setup(config,"fire")
	fire.custom_minimum_size.y = float(config.ui.layout.board_size)*0.25
	work.add_child(fire)
	fire.hide()
	fire_button = UI.button(copy.hold_fire,func(): pass,"primary")
	fire_button.name = "CraftAddFire"
	fire_button.button_down.connect(func(): fire_pressed = true)
	fire_button.button_up.connect(func(): fire_pressed = false)
	work.add_child(fire_button)
	fire_button.hide()
	selected_label = UI.label(copy.no_ingredients,int(config.ui.layout.minimum_font))
	box.add_child(selected_label)
	note = UI.label(copy.feed_hint if draft.mode == "known" else copy.unknown,int(config.ui.layout.minimum_font))
	box.add_child(note)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	reset_button = UI.button(copy.reset,reset_feeding)
	actions.add_child(reset_button)
	action_button = UI.button(copy.start,start_grinding,"primary")
	action_button.name = "CraftAdvance"
	actions.add_child(action_button)
	cancel_button = UI.button(copy.cancel,close)
	actions.add_child(cancel_button)
	for button: Button in quantity_buttons+[action_button,cancel_button,reset_button,fire_button]:
		button.add_theme_font_size_override("font_size",int(config.ui.layout.minimum_font))
	_refresh_shelf()

func _quantity(value: int) -> void:
	if stage != "feeding": return
	draft.quantity = value
	_refresh_shelf()

func feed(item_id: String) -> void:
	if stage != "feeding" or not config.materials.has(item_id): return
	var counts: Dictionary = Rules.ingredient_state(draft,config).counts
	if (int(counts.get(item_id,0))+1)*int(draft.quantity) > int(basis.player.items.get(item_id,0)): return
	if draft.ingredients.size() >= config.limits.ingredient_rows_max: return
	draft.ingredients.append({"item_id":item_id,"units":1})
	var values: Array = Rules.ingredient_state(draft,config).point
	if pointer_tween != null and pointer_tween.is_valid(): pointer_tween.kill()
	pointer_tween = create_tween()
	pointer_tween.tween_property(disk,"point",Vector2(values[0],values[1]),float(config.ui.visual.smoothing_seconds))
	pointer_tween.tween_callback(disk.queue_redraw)
	_sound("drop_sound")
	_refresh_shelf()

func reset_feeding() -> void:
	if stage != "feeding": return
	draft.ingredients.clear()
	disk.point = Vector2.ZERO
	disk.queue_redraw()
	_refresh_shelf()

func _refresh_shelf() -> void:
	for child: Node in shelf.get_children(): shelf.remove_child(child); child.queue_free()
	var counts: Dictionary = Rules.ingredient_state(draft,config).counts
	for id: String in config.materials:
		var stock := int(basis.player.items.get(id,0))
		if stock <= 0: continue
		var button := Ingredient.new()
		button.item_id = id
		button.name = "CraftMaterial_"+id
		button.text = config.materials[id].name+"\n"+String(config.ui.copy.ingredient_count).format({"stock":stock,"selected":counts.get(id,0)})
		button.add_theme_font_size_override("font_size",int(config.ui.layout.minimum_font))
		button.disabled = stage != "feeding" or (int(counts.get(id,0))+1)*int(draft.quantity) > stock
		button.pressed.connect(func(): feed(id))
		preload("res://scripts/ui/panel_materials.gd").apply_button(button,"paper_tag")
		shelf.add_child(button)
	var names: Array = []
	for id: String in counts: names.append(str(config.materials[id].name)+" × "+str(counts[id]))
	selected_label.text = config.ui.copy.no_ingredients if names.is_empty() else String(config.ui.copy.selected).format({"items":"、".join(names)})
	for index: int in range(quantity_buttons.size()):
		quantity_buttons[index].disabled = stage != "feeding"
		quantity_buttons[index].button_pressed = index+1 == int(draft.quantity)

func start_grinding() -> void:
	if stage == "ready" or stage == "retry":
		finalize()
		return
	if stage != "feeding": return
	var preflight := Rules.preflight_stock(draft,basis.player.items,config,catalog)
	if not preflight.success: note.text = preflight.message; return
	if draft.mode == "known" and not Rules.compatible(Rules.ingredient_state(draft,config).counts,config.targets[draft.target_id]):
		note.text = config.ui.copy.invalid_draft
		return
	stage = "grinding"
	accumulator = 0.0
	mortar.feeding = false
	stage_label.text = str(config.ui.copy.grinding)+" · "+str(config.ui.copy.hold_grind)
	note.text = config.ui.copy.hold_grind
	action_button.disabled = true
	reset_button.disabled = true
	_refresh_shelf()

func _process(delta: float) -> void:
	if config.is_empty(): return
	if stage == "feeding": disk.queue_redraw()
	if stage not in ["grinding","heating"]: return
	accumulator += delta
	var step := float(config.limits.tick_ms)/1000.0
	while accumulator >= step and stage in ["grinding","heating"]:
		accumulator -= step
		_sample()

func _sample() -> void:
	if stage == "grinding":
		if draft.grind_trace.size() >= config.limits.trace_samples_max: _incomplete(); return
		var offset: Vector2 = mortar.pointer-mortar.size*0.5
		var angle := fposmod(offset.angle(),TAU)
		var radius := offset.length()/(minf(mortar.size.x,mortar.size.y)*float(config.ui.visual.mortar_radius_ratio))
		draft.grind_trace.append({"tick":draft.grind_trace.size(),"pressed":mortar.holding and radius <= 1.0,"angle":int(angle/TAU*int(config.grind.angle_cycle)),"radius":clampi(roundi(radius*int(config.grind.radius_max)),0,int(config.grind.radius_max))})
		if draft.grind_trace.size() < 2: return
		var result := Rules.grind_result(draft.grind_trace,config,true)
		mortar.progress = minf(1.0,float(absi(int(result.travel)))/float(config.grind.required_travel))
		mortar.queue_redraw()
		note.text = config.ui.copy.spill if int(result.spill_steps) > 0 else String(config.ui.copy.grind_status).format({"percent":roundi(mortar.progress*100)})
		if int(result.ticks)%20 == 0 and mortar.holding: _sound("grind_sound")
		if result.complete:
			stage = "heating"
			stage_label.text = config.ui.copy.heating
			note.text = config.ui.copy.hold_fire
			mortar.hide()
			fire.show()
			fire_button.show()
			accumulator = 0.0
			_sound("fire_sound")
	elif stage == "heating":
		if draft.fire_trace.size() >= config.limits.trace_samples_max: _incomplete(); return
		draft.fire_trace.append({"tick":draft.fire_trace.size(),"pressed":fire_pressed})
		if draft.fire_trace.size() < 2: return
		var result := Rules.fire_result(draft.fire_trace,config,true)
		fire.temperature = float(result.temperature)/float(config.fire.maximum)
		fire.queue_redraw()
		note.text = String(config.ui.copy.fire_status).format({"seconds":snappedf(float(result.green_ms)/1000.0,0.1),"stability":roundi(float(result.stability_q)*100.0/float(config.fire.stability_scale))})
		if result.complete:
			stage = "ready"
			fire_button.disabled = true
			note.text = config.ui.copy.ready
			action_button.text = config.ui.copy.finalize
			action_button.disabled = false

func _incomplete() -> void:
	stage = "incomplete"
	note.text = config.ui.copy.invalid_draft
	fire_button.disabled = true

func finalize() -> void:
	if pending or stage not in ["ready","retry"]: return
	pending = true
	stage = "committing"
	action_button.disabled = true
	cancel_button.disabled = true
	note.text = config.ui.copy.saving
	var reply: Dictionary = await host.run_action("craft_finalize",{"expected_version":draft.base_version,"draft":draft.duplicate(true)},command_id)
	pending = false
	cancel_button.disabled = false
	if reply.get("success",false):
		stage = "done"
		stage_label.text = config.ui.copy.completed
		note.text = reply.message
		cancel_button.text = config.ui.copy.close
		_sound("success_sound")
	else:
		stage = "retry" if reply.get("error_code") == "SAVE_WRITE_FAILED" else "stale"
		note.text = reply.get("message",config.ui.copy.retry)
		action_button.disabled = stage != "retry"

func close() -> void:
	if pending: return
	stage = "closed"
	if pointer_tween != null and pointer_tween.is_valid(): pointer_tween.kill()
	_sound("cancel_sound")
	var window := get_parent() as Window
	if window != null: window.hide()

func _sound(key: String) -> void:
	var audio := get_tree().root.find_child("ShopAudio",true,false)
	if audio != null:
		var cue: String = str(config.ui.resources[key]).get_file().get_basename()
		audio.play_ui(cue)

extends SceneTree
const CORE_PATH := "res://scripts/shop/shelf_layout.gd"
var checks := 0
var failures := 0
var core: Script

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("SHELF LAYOUT FAIL: "+label)

func settings() -> Dictionary:
	return {"native_size":[1000,1000],"source_crop":[0,0,1000,1000],"category_order":["product","material","keepsake"],
		"contact_inset_px":2,"gap_px":[20,20],"rotation_max_degrees":0,"stack_offset_px":[-10,-10],"max_copies":3,
		"stack_darkening_step":0.1,"selection_lift_px":6,"selection_seconds":0.15,"quantity_format":"×%d",
		"shadow":{"width_factor":1.1,"height_px":12,"opacity":0.35,"texture_size":[128,32]},
		"paper":{"opacity":0.08,"texture_size":[256,256],"noise_frequency":0.04,"seed":7},
		"name_tag":{"font_path":"res://assets/fonts/LXGWWenKai-Regular.ttf","font_size":18,"text_color":"#382C24","paper_color":"#F3E9D6","border_color":"#B6A58C","border_width_px":1,"padding_px":[8,4],"drop_px":8},
		"quantity_tag":{"font_path":"res://assets/fonts/LXGWWenKai-Regular.ttf","font_size":16,"text_color":"#382C24","paper_color":"#F3E9D6","padding_px":[5,2],"offset_px":[12,-18]},
		"debug":{"toggle_key":"F3","line_width_px":1,"line_color":"#C64D3E","point_radius_px":3,"point_color":"#426A71"}}

func shelf(y: float = 500, left: float = 100, right: float = 900, scale_value: float = 0.5) -> Dictionary:
	return {"y":y,"x_start":left,"x_end":right,"depth_scale":scale_value,"light_tint_day":"#F4ECD8","light_tint_night":"#BCC6BF"}

func scene() -> Dictionary:
	return {"shelves":[shelf()],"shelf_layout":settings()}

func item(id: String = "a") -> Dictionary:
	return {"item_id":id,"size":[256,256],"bbox":[100,100,120,201],"bottom_y":200,"bottom_left":100,"bottom_width":20}

func visuals(value: Dictionary, mapping: Dictionary) -> Dictionary:
	return {"scenes":{"S04":value},"items":mapping}

func view(items: Dictionary, kinds: Dictionary = {}, batches: Array = []) -> Dictionary:
	return {"items":items,"catalog":{"items":kinds},"shop":{"batches":batches}}

func run() -> void:
	check(FileAccess.file_exists(CORE_PATH),"pure shelf core exists before rendering integration")
	if not FileAccess.file_exists(CORE_PATH):
		finish()
		return
	core = load(CORE_PATH)
	check(core != null and core.has_method("settings_valid") and core.has_method("layout"),"frozen pure API is available")
	if core == null or not core.has_method("layout"):
		finish()
		return
	check_validation()
	check_geometry_and_quantity()
	check_ordering()
	check_packing()
	check_purity()
	finish()

func check_validation() -> void:
	var value := scene()
	var mapping := {"a":item()}
	check(core.settings_valid(value,mapping),"valid finite native scene and measured support are accepted")
	var cases: Array = []
	var bad := value.duplicate(true)
	bad.shelves = []; cases.append([bad,"empty shelves"])
	bad = value.duplicate(true); bad.shelves[0].y = NAN; cases.append([bad,"NaN shelf line"])
	bad = value.duplicate(true); bad.shelves[0].depth_scale = INF; cases.append([bad,"infinite depth scale"])
	bad = value.duplicate(true); bad.shelves[0].depth_scale = 0; cases.append([bad,"zero scale"])
	bad = value.duplicate(true); bad.shelves[0].x_end = 99; cases.append([bad,"reversed shelf bounds"])
	bad = value.duplicate(true); bad.shelves[0].x_end = 1001; cases.append([bad,"shelf outside native crop"])
	bad = value.duplicate(true); bad.shelves[0].light_tint_night = "invalid"; cases.append([bad,"invalid tint"])
	bad = value.duplicate(true); bad.shelves.append(shelf(499)); cases.append([bad,"unordered shelf lines"])
	bad = value.duplicate(true); bad.shelf_layout.native_size[0] = 0; cases.append([bad,"zero native size"])
	bad = value.duplicate(true); bad.shelf_layout.source_crop[1] = NAN; cases.append([bad,"NaN crop"])
	bad = value.duplicate(true); bad.shelf_layout.source_crop[2] = 1001; cases.append([bad,"crop outside native"])
	bad = value.duplicate(true); bad.shelf_layout.source_crop = [10,0,5,1000]; cases.append([bad,"reversed crop"])
	bad = value.duplicate(true); bad.shelf_layout.gap_px = [24,16]; cases.append([bad,"reversed gap range"])
	bad = value.duplicate(true); bad.shelf_layout.contact_inset_px = -1; cases.append([bad,"negative contact inset"])
	bad = value.duplicate(true); bad.shelf_layout.rotation_max_degrees = INF; cases.append([bad,"infinite rotation"])
	bad = value.duplicate(true); bad.shelf_layout.stack_offset_px[0] = NAN; cases.append([bad,"NaN stack offset"])
	bad = value.duplicate(true); bad.shelf_layout.max_copies = 0; cases.append([bad,"zero copies"])
	bad = value.duplicate(true); bad.shelf_layout.category_order = ["product","product","material"]; cases.append([bad,"duplicate category"])
	bad = value.duplicate(true); bad.shelf_layout.quantity_format = "%d %s"; cases.append([bad,"unsafe quantity format"])
	bad = value.duplicate(true); bad.shelf_layout.shadow.opacity = NAN; cases.append([bad,"NaN shadow opacity"])
	bad = value.duplicate(true); bad.shelf_layout.paper.opacity = 1.1; cases.append([bad,"paper opacity outside unit range"])
	bad = value.duplicate(true); bad.shelf_layout.name_tag.font_path = "res://C:/outside.ttf"; cases.append([bad,"drive path disguised as a font resource"])
	bad = value.duplicate(true); bad.shelf_layout.quantity_tag.font_path = "res://assets//font.ttf"; cases.append([bad,"empty font path component"])
	bad = value.duplicate(true); bad.shelf_layout.name_tag.font_path = "res://scripts/font.gd"; cases.append([bad,"non-font resource type"])
	var with_labels := value.duplicate(true)
	with_labels.shelf_layout["labels"] = {"details_heading":"物品详情","all_items_heading":"柜内物品","overflow_heading":"抽屉中暂存的物品"}
	check(core.settings_valid(with_labels,mapping),"production headings may be supplied through the optional data block")
	for field: String in ["details_heading","all_items_heading","overflow_heading"]:
		bad = with_labels.duplicate(true); bad.shelf_layout.labels[field] = " "; cases.append([bad,"blank data heading / "+field])
	bad = with_labels.duplicate(true); bad.shelf_layout.labels.details_heading = 7; cases.append([bad,"non-string data heading"])
	bad = with_labels.duplicate(true); bad.shelf_layout.labels.erase("overflow_heading"); cases.append([bad,"incomplete heading block"])
	bad = value.duplicate(true); bad.shelf_layout["future_renderer"] = {"value":NAN}; cases.append([bad,"nonfinite extension parameter"])
	for entry: Array in cases:
		check(not core.settings_valid(entry[0],mapping),"reject "+str(entry[1]))
	var metadata: Array = [["bottom_y",NAN],["bottom_y",199],["bottom_width",0],["bottom_left",119],["size",[0,256]],["bbox",[0,0,300,201]],["alpha_bbox",[101,100,120,201]]]
	for pair: Array in metadata:
		var invalid := mapping.duplicate(true)
		invalid.a[pair[0]] = pair[1]
		check(not core.settings_valid(value,invalid),"reject malformed support metadata / "+str(pair[0])+" / "+str(pair[1]))
	bad = value.duplicate(true); bad.shelves[0].y = NAN
	var result: Dictionary = core.layout(view({"a":1}),visuals(bad,mapping))
	check(result.entries.is_empty() and result.overflow.is_empty(),"invalid settings return the frozen empty shape without emitting invalid geometry")

func check_geometry_and_quantity() -> void:
	var value := scene()
	var mapping := {"a":item()}
	var result: Dictionary = core.layout(view({"a":1}),visuals(value,mapping))
	check(result.entries.size() == 1,"single available ID produces one display group")
	if result.entries.size() == 1:
		var e: Dictionary = result.entries[0]
		check(e.pivot.is_equal_approx(Vector2(104.75,502)),"hand oracle: 20px support at half scale starts fully inside x=100 and touches y=502")
		check(e.support.is_equal_approx(Vector2(109.5,200)),"hand oracle uses measured bottom midpoint, not PNG canvas center")
		check(e.visible_rect.is_equal_approx(Rect2(100,452,10,50.5)),"hand oracle includes the entire exclusive-bottom visible rectangle")
		check(is_equal_approx(e.bottom_width*e.scale*float(value.shelf_layout.shadow.width_factor),11),"hand oracle: renderer shadow base becomes 11 native pixels")
		check(e.item_id == "a" and e.quantity == 1 and e.shelf_index == 0 and e.copy_count == 1,"frozen per-ID entry fields identify real quantity and shelf")
	for quantity: int in [1,2,3,4,30]:
		result = core.layout(view({"a":quantity}),visuals(value,mapping))
		check(result.entries.size() == 1 and result.entries[0].copy_count == mini(quantity,3) and result.entries[0].quantity == quantity,"quantity "+str(quantity)+" caps visuals without changing true amount")
	result = core.layout(view({"a":3}),visuals(value,mapping))
	if result.entries.size() == 1:
		check(result.entries[0].visible_rect.is_equal_approx(Rect2(100,432,30,70.5)),"hand oracle: three copies add native 20px left/up independent of half texture scale")
	result = core.layout(view({"a":0}),visuals(value,mapping))
	check(result.entries.is_empty() and result.overflow.is_empty(),"zero quantity never creates a placeholder or overflow entry")
	var large := mapping.duplicate(true)
	large.a["alpha_bbox"] = [98,98,122,203]
	result = core.layout(view({"a":1}),visuals(value,large))
	check(result.entries.size() == 1 and result.entries[0].visible_rect.size.is_equal_approx(Vector2(12,52.5)),"packing includes real feather alpha bounds rather than only alpha128 support bbox")

func check_ordering() -> void:
	var value := scene()
	var mapping: Dictionary = {}
	for id: String in ["p1","p2","p3","p4","m","gift"]:
		mapping[id] = item(id)
	var kinds := {"p1":{"kind":"product"},"p2":{"kind":"product"},"p3":{"kind":"product"},"p4":{"kind":"product"},"m":{"kind":"material"}}
	var batches := [{"item_id":"m","remaining":9,"at":999},{"item_id":"p2","remaining":0,"at":900},{"item_id":"p1","remaining":1,"at":1},{"item_id":"p2","remaining":1,"at":1000}]
	var result: Dictionary = core.layout(view({"gift":1,"p4":1,"p3":1,"p1":1,"m":1,"p2":1},kinds,batches),visuals(value,mapping))
	check(ids(result.entries) == ["p2","p1","p3","p4","m","gift"],"product/material/keepsake then first historical array position then stable ID, even after selling out and reacquiring")
	var second: Dictionary = core.layout(view({"p2":1,"m":1,"p1":1,"p3":1,"p4":1,"gift":1},kinds,batches),visuals(value,mapping))
	check(second == result,"dictionary input order never decides acquired order or geometry")
	result = core.layout(view({"unknown":2,"p1":1},kinds,batches),visuals(value,mapping))
	check(ids(result.entries) == ["p1"] and result.overflow == ["unknown"],"unknown item artwork is explicitly overflowed without stealing a valid shelf slot")

func check_packing() -> void:
	var value := scene()
	value.shelves = [shelf(500,100,119),shelf(600,100,111)]
	var mapping := {"a":item(),"b":item(),"c":item()}
	for id: String in mapping:
		mapping[id].item_id = id
	var result: Dictionary = core.layout(view({"a":1,"b":1,"c":1}),visuals(value,mapping))
	check(ids(result.entries) == ["a","b"] and result.entries[1].shelf_index == 1 and result.overflow == ["c"],"a full shelf advances once and genuinely full capacity becomes drawer overflow")
	value.shelves = [shelf(500,100,110)]
	result = core.layout(view({"a":1}),visuals(value,mapping))
	check(result.entries.size() == 1,"a 10px visible shape exactly fits a 10px shelf")
	value.shelves[0].x_end = 109
	result = core.layout(view({"a":1}),visuals(value,mapping))
	check(result.entries.is_empty() and result.overflow == ["a"],"one native pixel beyond the boundary is not accepted")
	value = scene()
	value.shelves = [shelf(500,100,200)]
	var wide := item("a")
	wide.bbox = [0,0,200,201]
	mapping = {"a":wide,"b":item("b")}
	result = core.layout(view({"a":1,"b":1}),visuals(value,mapping))
	check(result.entries.size() == 1 and result.overflow == ["b"],"wide upper silhouette controls packing even when support is only 20px")
	value.shelf_layout.rotation_max_degrees = 1.5
	value.shelves = [shelf(500,100,900)]
	result = core.layout(view({"a":3,"b":2}),visuals(value,mapping))
	check(result.entries.size() == 2,"small native micro-rotations retain usable shelf capacity")
	for e: Dictionary in result.entries:
		check(absf(e.rotation_degrees) <= 1.5 and not is_zero_approx(e.rotation_degrees),"item-specific deterministic angle stays in the nontrivial configured range")
		var union := Rect2()
		var first := true
		var bounds: Array = mapping[e.item_id].bbox
		for copy_index: int in range(e.copy_count):
			for corner: Vector2 in [Vector2(bounds[0],bounds[1]),Vector2(bounds[2],bounds[1]),Vector2(bounds[2],bounds[3]),Vector2(bounds[0],bounds[3])]:
				var point: Vector2 = e.pivot+((corner-e.support)*e.scale+Vector2(-10,-10)*copy_index).rotated(deg_to_rad(e.rotation_degrees))
				union = Rect2(point,Vector2.ZERO) if first else union.expand(point)
				first = false
		check(e.visible_rect.is_equal_approx(union),"visible_rect contains all rotated copy corners in the renderer's declared native transform")
	if result.entries.size() == 2:
		check(result.entries[0].visible_rect.end.x+20 <= result.entries[1].visible_rect.position.x+0.0001,"full rotated groups retain at least the configured visible safety gap")
	value.shelves = [shelf(10,100,900)]
	result = core.layout(view({"a":1}),visuals(value,mapping))
	check(result.entries.is_empty() and result.overflow == ["a"],"a group extending above the source crop is overflowed, not clipped silently")

func check_purity() -> void:
	var value := scene()
	value.shelf_layout.gap_px = [16,24]
	value.shelf_layout.rotation_max_degrees = 1.5
	var mapping := {"a":item(),"b":item("b")}
	var data := visuals(value,mapping)
	var inventory := view({"a":3,"b":1})
	var before_data := data.duplicate(true)
	var before_view := inventory.duplicate(true)
	seed(987654)
	var expected := randi()
	seed(987654)
	var result: Dictionary = core.layout(inventory,data)
	check(randi() == expected,"layout never consumes the game's global RNG stream")
	check(data == before_data and inventory == before_view,"pure layout changes no config, stock, source batch or save field")
	check(core.layout(inventory,data) == result,"a separate layout call regenerates identical positions, copies and angles")
	if result.entries.size() == 2:
		var gap: float = result.entries[1].visible_rect.position.x-result.entries[0].visible_rect.end.x
		check(gap >= 16 and gap <= 24.0001,"item-seeded safety spacing lies within the configured native interval")

func ids(entries: Array) -> Array:
	var result: Array = []
	for entry: Dictionary in entries:
		result.append(entry.item_id)
	return result

func finish() -> void:
	print("SHELF LAYOUT: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

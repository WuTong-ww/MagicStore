extends RefCounted
## Presentation only. No GameState/People/Story access, state actions or RNG.
const PATH := "res://data/ui/panel_materials.json"
const Surface = preload("res://scripts/ui/panel_material_style.gd")
const Motion = preload("res://scripts/ui/panel_material_motion.gd")
const Fonts = preload("res://scripts/ui/font_policy.gd")
const IDS := ["notebook","letter","paper_cream","paper_blue","paper_lilac","tag_cream","tag_blue","tag_lilac","tag_neutral","wax_seal","paper_tag","red_stamp","vine","wood"]
const ROLE_VARIANTS := {"notebook":["default"],"dialogue":["letter"],"paper":["cream","blue","lilac"],"smalltag":["cream","blue","lilac","neutral"],"plain":["default"],"titledivider":["default"],"wood":["default"]}

static func _keys(value: Variant, fields: Array) -> bool:
	return value is Dictionary and value.size() == fields.size() and fields.all(func(key: String) -> bool: return value.has(key))

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

static func _vector(value: Variant, size: int, minimum: float, maximum: float, integer: bool = false) -> bool:
	return value is Array and value.size() == size and value.all(func(v: Variant) -> bool: return _number(v,minimum,maximum) and (not integer or v == floor(float(v))))

static func _color(value: Variant) -> bool:
	return value is String and value.length() in [7,9] and value.begins_with("#") and Color.html_is_valid(value)

static func config_valid(value: Variant) -> bool:
	if not _keys(value,["version","assets","roles","aliases","shadow","backdrop","layout","effects","audio","evidence","empty_slot","copy","colors"]) or not _number(value.version,1,1):
		return false
	if not _keys(value.assets,IDS) or not _keys(value.roles,ROLE_VARIANTS.keys()) or value.aliases != {"letter":"dialogue"}:
		return false
	for id: String in IDS:
		var row: Variant = value.assets[id]
		var fields := ["path","mode","region","margins","native_size"]
		if id == "notebook": fields.append("book_regions")
		if not _keys(row,fields) or row.path != ("res://assets/ui/title_wood_sign.png" if id == "wood" else "res://assets/ui/material_v3/"+id+".png") or row.mode not in ["nine_slice","texture","book"]:
			return false
		if (id == "notebook") != (row.mode == "book") or not row.region is Array or (not row.region.is_empty() and not _vector(row.region,4,0,16384,true)) or not _vector(row.margins,4,0,16384,true) or not _vector(row.native_size,2,0,16384,true):
			return false
		if (row.native_size[0] == 0) != (row.native_size[1] == 0): return false
		if not row.region.is_empty() and (row.region[2] <= 0 or row.region[3] <= 0): return false
		if row.native_size[0] > 0:
			var width := float(row.native_size[0])
			var height := float(row.native_size[1])
			if not row.region.is_empty():
				if row.region[0]+row.region[2] > width or row.region[1]+row.region[3] > height: return false
				width = row.region[2]
				height = row.region[3]
			if row.margins[0]+row.margins[2] >= width or row.margins[1]+row.margins[3] >= height: return false
		if id == "notebook":
			if not _keys(row.book_regions,["left","spine","right"]): return false
			for part: String in ["left","spine","right"]:
				var rect: Variant = row.book_regions[part]
				if not _vector(rect,4,0,1) or rect[2] <= 0 or rect[3] <= 0 or rect[0]+rect[2] > 1 or rect[1]+rect[3] > 1: return false
			var left: Array = row.book_regions.left
			var spine: Array = row.book_regions.spine
			var right: Array = row.book_regions.right
			if not is_zero_approx(float(left[0])) or not is_equal_approx(float(left[0]+left[2]),float(spine[0])) or not is_equal_approx(float(spine[0]+spine[2]),float(right[0])) or not is_equal_approx(float(right[0]+right[2]),1.0): return false
			if row.native_size[0] > 0:
				var source_width: float = row.region[2] if not row.region.is_empty() else row.native_size[0]
				var source_height: float = row.region[3] if not row.region.is_empty() else row.native_size[1]
				if row.margins[0]+row.margins[2] >= source_width*minf(float(left[2]),float(right[2])) or row.margins[1]+row.margins[3] >= source_height*minf(float(left[3]),float(right[3])): return false
	for role: String in ROLE_VARIANTS:
		var row: Variant = value.roles[role]
		if not _keys(row,["default","variants","fallback"]) or not _keys(row.variants,ROLE_VARIANTS[role]) or row["default"] not in row.variants or not _color(row.fallback): return false
		for variant: String in row.variants:
			if row.variants[variant] not in IDS and not (role == "plain" and row.variants[variant] == ""): return false
		if role == "plain" and row.variants["default"] != "": return false
	var shadow: Variant = value.shadow
	if not _keys(shadow,["color","opacity","offset","blur","hover_opacity"]) or not _color(shadow.color) or not _number(shadow.opacity,0,1) or not _number(shadow.hover_opacity,shadow.opacity,1) or not _vector(shadow.offset,2,-64,64) or not _number(shadow.blur,0,64): return false
	if not _keys(value.backdrop,["color","opacity"]) or not _color(value.backdrop.color) or not _number(value.backdrop.opacity,0,1): return false
	var layout: Variant = value.layout
	if not _keys(layout,["content_margins","fallback_corner_radius","book_spine_width","book_spine_gap","book_page_insets","divider_height","divider_gap","stamp_size","drag_preview_size","slice_border","book_minimum_size","book_preferred_width","book_preferred_height"]): return false
	if not _vector(layout.content_margins,4,0,128) or not _vector(layout.book_page_insets,4,0,128) or not _vector(layout.stamp_size,2,1,512) or not _vector(layout.drag_preview_size,2,1,1024) or not _vector(layout.book_minimum_size,2,1,2048): return false
	for key: String in ["fallback_corner_radius","book_spine_width","book_spine_gap","divider_height","divider_gap","slice_border","book_preferred_width","book_preferred_height"]:
		if not _number(layout[key],0.01,2048): return false
	var effects: Variant = value.effects
	if not _keys(effects,["seed_namespace","paper_hover_y","hover_seconds","wood_sway_degrees","wood_sway_hz","candidate_degrees","drag_sway_degrees","drag_sway_hz","stamp_seconds","stamp_scale_from","stamp_scale_to","card_y_scale","contact_shadow_height","contact_shadow_width_ratio"]) or not effects.seed_namespace is String or effects.seed_namespace.strip_edges().is_empty(): return false
	if not _number(effects.paper_hover_y,-16,0) or not _number(effects.hover_seconds,0.01,5) or not _number(effects.stamp_seconds,0.01,5) or not _number(effects.stamp_scale_from,1,3) or not _number(effects.stamp_scale_to,1,1) or not _number(effects.card_y_scale,0.5,1) or not _number(effects.contact_shadow_width_ratio,0.1,1) or not _number(effects.contact_shadow_height,1,64): return false
	for key: String in ["wood_sway_degrees","candidate_degrees","drag_sway_degrees"]:
		if not _number(effects[key],0,3): return false
	for key: String in ["wood_sway_hz","drag_sway_hz"]:
		if not _number(effects[key],0,8): return false
	if not _keys(value.audio,["paper","wood","wax"]) or not value.audio.values().all(func(v: Variant) -> bool: return v in ["page","click","confirm"]): return false
	if not _keys(value.evidence,["fact","testimony","tool","neutral"]) or not value.evidence.values().all(func(v: Variant) -> bool: return v in value.roles.smalltag.variants): return false
	if not _keys(value.empty_slot,["color","width","dash","gap"]) or not _color(value.empty_slot.color): return false
	for key: String in ["width","dash","gap"]:
		if not _number(value.empty_slot[key],0.01,64): return false
	if not _keys(value.colors,["ink","light_ink","stamp"]) or not value.colors.values().all(func(v: Variant) -> bool: return _color(v)): return false
	return _keys(value.copy,["missing"]) and value.copy.missing is String and not value.copy.missing.strip_edges().is_empty()

static func load_config() -> Dictionary:
	return preload("res://scripts/ui/packed_ui_data.gd").load_web(PATH,config_valid)

static func asset_status(id: String, config: Dictionary = {}) -> Dictionary:
	if config.is_empty(): config = load_config()
	if not config_valid(config) or not config.assets.has(id): return {"ready":false,"missing":[id],"texture":null}
	var row: Dictionary = config.assets[id]
	if row.native_size[0] == 0 or not ResourceLoader.exists(row.path): return {"ready":false,"missing":[row.path],"texture":null}
	var texture := load(str(row.path)) as Texture2D
	if texture == null or texture.get_width() != int(row.native_size[0]) or texture.get_height() != int(row.native_size[1]): return {"ready":false,"missing":[row.path],"texture":null}
	if not row.region.is_empty():
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(row.region[0],row.region[1],row.region[2],row.region[3])
		texture = atlas
	return {"ready":true,"missing":[],"texture":texture}

static func _resolve(role: String, variant: String, config: Dictionary) -> Dictionary:
	var canonical: String = str(config.aliases.get(role,role))
	if not config.roles.has(canonical): return {}
	var row: Dictionary = config.roles[canonical]
	if variant.is_empty(): variant = row["default"]
	if not row.variants.has(variant): return {}
	return {"role":role,"render_role":canonical,"variant":variant,"asset_id":row.variants[variant],"fallback_color":row.fallback}

static func style_for(role: String, variant: String = "", config: Dictionary = {}) -> StyleBox:
	if config.is_empty(): config = load_config()
	if not config_valid(config): return null
	var resolved := _resolve(role,variant,config)
	if resolved.is_empty(): return null
	if resolved.render_role == "plain": return StyleBoxEmpty.new()
	var status := asset_status(resolved.asset_id,config)
	var style := Surface.new()
	style.configure(config.assets[resolved.asset_id],config,status.texture,resolved.fallback_color)
	style.shadow_enabled = resolved.render_role != "titledivider"
	return style

static func _set_meta(control: Control, semantic_role: String, resolved: Dictionary, status: Dictionary, config: Dictionary) -> Dictionary:
	control.set_meta("material_role",semantic_role)
	control.set_meta("render_role",resolved.render_role)
	control.set_meta("material_variant",resolved.variant)
	control.set_meta("material_ready",status.ready)
	control.set_meta("material_audio_key",config.audio.wood if resolved.render_role == "wood" else config.audio.paper)
	return {"success":true,"ready":status.ready,"fallback":not status.ready,"role":semantic_role,"variant":resolved.variant,"asset_id":resolved.asset_id,"missing":status.missing.duplicate()}

static func apply_panel(control: Control, role: String, variant: String = "") -> Dictionary:
	var config := load_config()
	if control == null or config.is_empty(): return {"success":false}
	var resolved := _resolve(role,variant,config)
	if resolved.is_empty(): return {"success":false}
	var style := style_for(role,variant,config)
	if style == null: return {"success":false}
	control.add_theme_stylebox_override("panel",style)
	var status := {"ready":true,"missing":[]} if resolved.render_role == "plain" else asset_status(resolved.asset_id,config)
	if style is Surface:
		_bind_motion(control,style,resolved.render_role,config)
	return _set_meta(control,role,resolved,status,config)

static func _bind_motion(control: Control, style: StyleBox, role: String, config: Dictionary) -> void:
	var old := control.get_node_or_null("PanelMaterialMotion")
	if old != null:
		control.remove_child(old)
		old.queue_free()
	var motion := Motion.new()
	motion.name = "PanelMaterialMotion"
	motion.configure(control,style,role,config)
	control.add_child(motion)

static func content_rects(size: Vector2, role: String = "notebook") -> Array:
	var config := load_config()
	if config.is_empty() or role != "notebook": return []
	var layout: Dictionary = config.layout
	var insets: Array = layout.book_page_insets
	var half := maxf(0.0,(size.x-float(layout.book_spine_width))/2.0)
	var width := maxf(0.0,half-float(layout.book_spine_gap)-float(insets[0])-float(insets[2]))
	var height := maxf(0.0,size.y-float(insets[1])-float(insets[3]))
	return [Rect2(Vector2(insets[0],insets[1]),Vector2(width,height)),Rect2(Vector2(half+float(layout.book_spine_width)+float(layout.book_spine_gap)+float(insets[0]),insets[1]),Vector2(width,height))]

static func evidence_role(public_kind: String) -> String:
	return public_kind if public_kind in ["fact","testimony","tool"] else "neutral"

static func _stable_angle(key: String, config: Dictionary, limit: float) -> float:
	var value := (str(config.effects.seed_namespace)+"|"+key).sha256_text().substr(0,15).hex_to_int()
	return (float(value)/float(0xfffffffffffffff)*2.0-1.0)*limit

static func _apply_button_asset(button: BaseButton, id: String, role: String, config: Dictionary) -> Dictionary:
	var status := asset_status(id,config)
	if status.ready:
		var style := Surface.new()
		style.configure(config.assets[id],config,status.texture,str(config.roles.paper.fallback))
		# New controls have not inherited the application Theme yet. Use the
		# validated material margins rather than the engine's temporary default.
		for state: String in ["normal","hover","pressed","disabled","focus"]:
			if state == "focus": continue
			button.add_theme_stylebox_override(state,style)
		button.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
		_bind_motion(button,style,"wood" if role == "wood" else "paper",config)
	else:
		# Preserve the old functional body while art is pending, but never paint
		# the old opaque/gold focus panel over a material. Shadow is the cue.
		var focus := Surface.new()
		focus.configure(config.assets[id],config,null,str(config.roles.plain.fallback))
		focus.draw_body = false
		button.add_theme_stylebox_override("focus",focus)
		_bind_motion(button,focus,"wood" if role == "wood" else "paper",config)
	var ink := Color(config.colors.light_ink if role in ["wax","wood"] else config.colors.ink)
	for slot: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_disabled_color"]:
		button.add_theme_color_override(slot,ink)
	for slot: String in ["icon_normal_color","icon_hover_color","icon_pressed_color","icon_focus_color","icon_disabled_color"]:
		button.add_theme_color_override(slot,ink)
	var resolved := {"render_role":role,"variant":"default","asset_id":id}
	return _set_meta(button,role,resolved,status,config)

static func apply_button(button: BaseButton, role: String, _key: String = "") -> Dictionary:
	var config := load_config()
	if button == null or config.is_empty() or role not in ["wax","paper_tag","wood"]: return {"success":false}
	var result := _apply_button_asset(button,"wax_seal" if role == "wax" else role,role,config)
	button.set_meta("material_audio_key",config.audio["wax" if role == "wax" else "wood" if role == "wood" else "paper"])
	return result

static func apply_evidence(button: BaseButton, public_kind: String, key: String = "") -> Dictionary:
	var config := load_config()
	if config.is_empty() or button == null: return {"success":false}
	var kind := evidence_role(public_kind)
	var variant: String = config.evidence[kind]
	var result := _apply_button_asset(button,str(config.roles.smalltag.variants[variant]),"evidence_"+kind,config)
	_bind_resize(button,"material_pivot_sync",_sync_pivot.bind(button))
	_bind_static_angle(button,_stable_angle(key,config,float(config.effects.candidate_degrees)))
	button.set_meta("material_variant",variant)
	button.set_meta("render_role","smalltag")
	return result

static func stamp_texture() -> Texture2D:
	var status := asset_status("red_stamp")
	return status.texture

static func animate_stamp(control: Control) -> Tween:
	var config := load_config()
	if control == null or config.is_empty(): return null
	var previous: Variant = control.get_meta("material_stamp_tween") if control.has_meta("material_stamp_tween") else null
	if previous is Tween and previous.is_valid(): previous.kill()
	control.pivot_offset = control.size/2.0
	var reduced: bool = not bool(control.get_meta("material_motion_enabled",true))
	if control.is_inside_tree():
		var wind := control.get_node_or_null("/root/WindField")
		if wind != null and bool(wind.get("reduced_motion")): reduced = true
	if not control.is_inside_tree() or reduced:
		control.scale = Vector2.ONE*float(config.effects.stamp_scale_to)
		return null
	control.scale = Vector2.ONE*float(config.effects.stamp_scale_from)
	var tween := control.create_tween()
	tween.tween_property(control,"scale",Vector2.ONE*float(config.effects.stamp_scale_to),float(config.effects.stamp_seconds))
	control.set_meta("material_stamp_tween",tween)
	return tween

static func apply_candidate(button: BaseButton, key: String = "", selected: bool = false) -> Dictionary:
	var config := load_config()
	if button == null or config.is_empty(): return {"success":false}
	var result := _apply_button_asset(button,"paper_cream","candidate",config)
	button.set_meta("render_role","paper")
	_bind_resize(button,"material_pivot_sync",_sync_pivot.bind(button))
	_bind_static_angle(button,_stable_angle(key,config,float(config.effects.candidate_degrees)))
	button.set_meta("material_selected",selected)
	var remembered: Variant = button.get_meta("material_stamp_node") if button.has_meta("material_stamp_node") else null
	var stamp: Control = remembered if is_instance_valid(remembered) and remembered is Control and remembered.get_parent() == button else button.get_node_or_null("MaterialSelectionStamp") as Control
	if stamp == null:
		var image := stamp_texture()
		if image != null:
			var picture := TextureRect.new()
			picture.texture = image
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			stamp = picture
		else:
			var placeholder := Panel.new()
			var wax := StyleBoxFlat.new()
			wax.bg_color = Color(config.colors.stamp)
			wax.set_corner_radius_all(int(minf(float(config.layout.stamp_size[0]),float(config.layout.stamp_size[1]))/2.0))
			placeholder.add_theme_stylebox_override("panel",wax)
			placeholder.set_meta("material_ready",false)
			stamp = placeholder
		stamp.name = "MaterialSelectionStamp"
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stamp.size = Vector2(config.layout.stamp_size[0],config.layout.stamp_size[1])
		stamp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		stamp.position = Vector2(button.size.x-stamp.size.x,0)
		button.add_child(stamp)
		button.set_meta("material_stamp_node",stamp)
	_bind_resize(button,"material_stamp_layout_sync",_sync_stamp.bind(button,stamp,config.layout.stamp_size))
	stamp.visible = selected
	# Styling/rebuilding a committed selection is static. Only the consumer's
	# successful saved action feedback calls animate_stamp().
	return result

static func make_divider() -> TextureRect:
	var node := TextureRect.new()
	node.name = "MaterialTitleDivider"
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var config := load_config()
	if not config.is_empty():
		node.custom_minimum_size.y = config.layout.divider_height
		node.texture = asset_status("vine",config).texture
	return node

static func make_drag_preview(text: String, public_kind: String, key: String) -> Control:
	var node := PanelContainer.new()
	node.name = "MaterialDragPreview"
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var config := load_config()
	if config.is_empty(): return node
	apply_panel(node,"smalltag",str(config.evidence[evidence_role(public_kind)]))
	node.custom_minimum_size = Vector2(config.layout.drag_preview_size[0],config.layout.drag_preview_size[1])
	node.rotation_degrees = _stable_angle(key,config,float(config.effects.drag_sway_degrees))
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color",Color(config.colors.ink))
	if Fonts.composite() != null: label.add_theme_font_override("font",Fonts.composite())
	node.add_child(label)
	_bind_motion(node,node.get_theme_stylebox("panel"),"drag",config)
	return node

static func backdrop_color() -> Color:
	var config := load_config()
	if config.is_empty(): return Color.TRANSPARENT
	var color := Color(config.backdrop.color)
	color.a = config.backdrop.opacity
	return color

static func _bind_resize(control: Control, key: String, callback: Callable) -> void:
	var previous: Variant = control.get_meta(key,Callable())
	if previous is Callable and previous.is_valid() and control.resized.is_connected(previous): control.resized.disconnect(previous)
	control.set_meta(key,callback)
	control.resized.connect(callback)
	callback.call()
	callback.call_deferred()

static func _sync_pivot(control: Variant) -> void:
	if is_instance_valid(control) and control is Control: control.pivot_offset = control.size/2.0

static func _bind_static_angle(button: BaseButton, angle: float) -> void:
	button.set_meta("material_static_angle",angle)
	button.rotation_degrees = angle
	_install_static_angle.call_deferred(weakref(button))

static func _install_static_angle(reference: WeakRef) -> void:
	var button: BaseButton = reference.get_ref()
	if not is_instance_valid(button) or not button.is_inside_tree(): return
	var container := button.get_parent() as Container
	if container != null and not container.get_meta("material_angles_bound",false):
		container.sort_children.connect(_queue_container_angles.bind(weakref(container)))
		container.set_meta("material_angles_bound",true)
	_restore_static_angle(reference)

static func _queue_container_angles(reference: WeakRef) -> void:
	var container: Container = reference.get_ref()
	if not is_instance_valid(container): return
	for child: Node in container.get_children():
		if child is BaseButton and child.has_meta("material_static_angle"): _restore_static_angle.call_deferred(weakref(child))

static func _restore_static_angle(reference: WeakRef) -> void:
	var button: BaseButton = reference.get_ref()
	if is_instance_valid(button) and button.is_inside_tree() and not button.is_queued_for_deletion(): button.rotation_degrees = float(button.get_meta("material_static_angle",0.0))

static func _sync_stamp(button: Variant, stamp: Variant, size: Array) -> void:
	if not is_instance_valid(button) or not is_instance_valid(stamp) or not button is BaseButton or not stamp is Control or stamp.get_parent() != button: return
	stamp.size = Vector2(size[0],size[1])
	stamp.position = Vector2(button.size.x-stamp.size.x,0)
	stamp.pivot_offset = stamp.size/2.0

static func _sync_card(button: Variant, art: Variant, shadow: Variant, config: Dictionary) -> void:
	if not is_instance_valid(button) or not is_instance_valid(art) or not is_instance_valid(shadow) or not button is BaseButton or not art is TextureRect or not shadow is Panel: return
	art.pivot_offset = Vector2(art.size.x/2.0,art.size.y)
	art.scale.y = 1.0 if art.get_meta("case_card_ratio",false) else float(config.effects.card_y_scale)
	shadow.size = Vector2(art.size.x*float(config.effects.contact_shadow_width_ratio),float(config.effects.contact_shadow_height))
	shadow.position = art.position+Vector2((art.size.x-shadow.size.x)/2.0,art.size.y-shadow.size.y/2.0)

static func apply_tarot_card(button: BaseButton, art: TextureRect, _key: String = "") -> Dictionary:
	var config := load_config()
	if button == null or art == null or config.is_empty(): return {"success":false}
	for state: String in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	button.set_meta("material_role","tarot_card")
	art.pivot_offset = Vector2(art.size.x/2.0,art.size.y)
	art.scale.y = 1.0 if art.get_meta("case_card_ratio",false) else float(config.effects.card_y_scale)
	art.set_meta("material_card_y_scale",art.scale.y)
	var shadow := button.get_node_or_null("MaterialContactShadow") as Panel
	if shadow == null:
		shadow = Panel.new()
		shadow.name = "MaterialContactShadow"
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shadow.set_meta("material_contact_shadow",true)
		button.add_child(shadow)
		button.move_child(shadow,0)
	var box := StyleBoxFlat.new()
	var color := Color(config.shadow.color)
	color.a = config.shadow.opacity
	box.bg_color = color
	box.set_corner_radius_all(int(config.effects.contact_shadow_height))
	box.shadow_color = color
	box.shadow_size = int(config.shadow.blur)
	shadow.add_theme_stylebox_override("panel",box)
	var update := _sync_card.bind(button,art,shadow,config)
	_bind_resize(art,"material_card_layout_sync",update)
	_bind_resize(button,"material_card_layout_sync",update)
	return {"success":true,"role":"tarot_card","ready":art.texture != null,"fallback":false}

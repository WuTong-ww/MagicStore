extends Control

const UI = preload("res://scripts/ui/ui_kit.gd")
const CardChoice = preload("res://scripts/ui/card_choice.gd")
const ArrivalUI = preload("res://scripts/ui/arrival_ui.gd")
## Seven public destinations share layout, while all actions go through GameState.

@export var page := "inventory"
var host
var body: VBoxContainer
var show_details := false
var visuals: Dictionary = {}
var cabinet_open := true
var inventory_filter := "all"
var market_mode := "buy"
var market_quantity := 1
var market_action_buttons: Array[Button] = []
const TITLES := {"exterior":"灯下的杂货铺", "inventory":"储物柜与经营账簿", "workshop":"需求、研究与制作", "market":"原料商店", "gathering":"外出采集"}
const SOURCES := {"purchase":"采购", "gather":"采集", "gift":"顾客赠料", "craft":"制作", "legacy_or_case":"开局或案例", "legacy":"开局或旧档", "case_payment":"问卜报酬"}
const ICONS := {"restorative_draught":0,"clarity_crystal":1,"calming_incense":2,"lavender":3,"quartz":4,"moon_dust":5,"spring_water":6,"silver_leaf":7,"bookmark":8}
const SceneArt = preload("res://scripts/shop/scene_visual.gd")
const ItemArt = preload("res://scripts/shop/item_visual.gd")
const ContentUI = preload("res://scripts/shop/content_ui.gd")
var content_settings: Dictionary = {}
var selected_variants: Dictionary = {}
var expanded_uses: Dictionary = {}
var content_action_pending := false
var scene_visual: Control
var shelf_view: Control
var selected_inventory_item := ""
const ShelfView = preload("res://scripts/shop/shelf_view.gd")
var side_panel: PanelContainer
var drawer: Control

func _ready() -> void:
	visuals = ItemArt.load_config()
	content_settings = ContentUI.load_config()
	scene_visual = SceneArt.new()
	scene_visual.name = "SceneArtwork"
	add_child(scene_visual)
	scene_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene_visual.setup(page)
	if page == "inventory":
		scene_visual.hotspot("cabinet",_toggle_cabinet)
	drawer = preload("res://scripts/ui/paper_drawer.gd").new()
	drawer.name = "SceneControls"
	add_child(drawer)
	side_panel = drawer.panel
	body = drawer.content
	body.add_theme_constant_override("separation",int(content_settings.get("layout",{}).get("gap",10)))
	resized.connect(_layout_scene_controls)
	_layout_scene_controls()
	refresh()

func _layout_scene_controls() -> void:
	if visuals.is_empty():
		return
	var shell: Dictionary = preload("res://scripts/ui/shell_config.gd").load_config()
	drawer.position = Vector2(0,shell.layout.drawer_inset_top)
	drawer.size = Vector2(size.x,maxf(0,size.y-shell.layout.drawer_inset_top-shell.layout.drawer_inset_bottom))

func refresh() -> void:
	if not is_instance_valid(body):
		return
	drawer.begin_content_update()
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	text(TITLES.get(page, "店铺"), 26)
	scene_visual.refresh()
	var view: Dictionary = GameState.shop_view()
	if view.is_empty():
		if is_instance_valid(shelf_view):
			shelf_view.update_inventory({},GameState.player_snapshot(),false)
		text("请先打开存档簿，新建或继续经营。")
		return
	if content_settings.is_empty() and page != "exterior":
		return
	match page:
		"exterior":
			var snapshot: Dictionary = GameState.player_snapshot()
			var minute := int(snapshot.get("clock_minutes", 540)) % 1440
			var is_open := minute >= 540 and minute < 1320
			text("营业牌：%s · 当前时间 %02d:%02d" % ["营业中" if is_open else "今日打烊", int(minute / 60), minute % 60])
			text("灯已经亮起。候客、预约和旧故事都在这里继续。")
			button("看看正在等候的来客", func(): host.open_people())
			button("等待 30 分钟", func(): await act("wait", {"minutes":30}))
			button("进入前台", func(): host.show_screen("front"))
		"inventory":
			_inventory(view)
		"workshop":
			_workshop(view)
		"market":
			_market(view)
		"gathering":
			_gathering(view)
	drawer.balance_content_pages()

func _toggle_cabinet() -> void:
	cabinet_open = not cabinet_open
	refresh()

func _inventory(view: Dictionary) -> void:
	if not SceneArt.config_valid(visuals):
		if is_instance_valid(shelf_view):
			shelf_view.update_inventory({},GameState.player_snapshot(),false)
		var unavailable := UI.label(str(ItemArt.load_settings().shelf_unavailable),18)
		unavailable.name = "ShelfUnavailable"
		body.add_child(unavailable)
		return
	text("口碑 %d · 经营经验 %d · 复盘成长 %d · 当前客流加成 %d" % [view.shop.reputation, view.shop.experience, view.shop.review_growth, view.arrival_bonus])
	scene_visual.cabinet_state = "open" if cabinet_open else "closed"
	scene_visual.refresh()
	_build_inventory_shelves(view)
	button(visuals.scene_settings.cabinet_open_label if cabinet_open else visuals.scene_settings.cabinet_closed_label,_toggle_cabinet)
	if not cabinet_open:
		text("柜门已经合上。打开后可查看商品、原料、来源与用途。", 16)
		return
	var filter := CardChoice.new()
	filter.add_item("全部物品")
	filter.set_item_metadata(0, "all")
	filter.add_item("原料")
	filter.set_item_metadata(1, "material")
	filter.add_item("成品商品")
	filter.set_item_metadata(2, "product")
	filter.select(["all", "material", "product"].find(inventory_filter))
	filter.item_selected.connect(func(index: int):
		inventory_filter = str(filter.get_item_metadata(index))
		refresh())
	body.add_child(filter)
	var shelf_labels: Dictionary = visuals.scenes.S04.shelf_layout.labels
	if not selected_inventory_item.is_empty() and int(view.items.get(selected_inventory_item,0)) <= 0:
		selected_inventory_item = ""
	if not selected_inventory_item.is_empty():
		text(str(shelf_labels.details_heading),20)
		_inventory_item_actions(view,selected_inventory_item)
		text(str(shelf_labels.all_items_heading),20)
	if not shelf_view.layout_result.get("overflow",[]).is_empty():
		text(str(shelf_labels.overflow_heading),20)
		for overflow_id: String in shelf_view.layout_result.overflow:
			if overflow_id != selected_inventory_item:
				_inventory_item_actions(view,overflow_id)
		text(str(shelf_labels.all_items_heading),20)
	for id: String in view.items:
		if int(view.items[id]) <= 0:
			continue
		var item: Dictionary = view.catalog.items.get(id,{})
		if inventory_filter != "all" and item.get("kind", "") != inventory_filter:
			continue
		if id == selected_inventory_item or id in shelf_view.layout_result.get("overflow",[]):
			continue
		_inventory_item_actions(view,id)
	var sales_shown := {}
	for entry: Dictionary in view.shop.ledger:
		if entry.category == "product" and not entry.result.get("used", false) and not sales_shown.has(entry.result.item_id):
			var item_id: String = entry.result.item_id
			sales_shown[item_id] = true
			var actions: Array = _use_actions(view,item_id).filter(func(row: Dictionary) -> bool: return row.target == "sale")
			if not actions.is_empty():
				var sale_row := _item_row(item_id,str(view.catalog.items[item_id].name))
				_add_use_actions(sale_row,actions,item_id)
	for option: Dictionary in view.shop.unlocked_options:
		if not option.get("used", false):
			button("澄心晶 · 温和追问已知往事", func(): await act("use_unlocked_option", {"item_use_id":option.item_use_id}))
	for effect: Dictionary in GameState.divination_effects("C"):
		if effect.kind == "review_growth" and effect.effect_id not in view.shop.reviews:
			button("复盘这次判断 · 20 分钟／5 精力", func(): await act("review_case", {"effect_id":effect.effect_id}))
	text("库存来源", 20)
	var details := CheckButton.new()
	details.text = str(content_settings.get("copy",{}).get("source_details",""))
	details.button_pressed = show_details
	details.toggled.connect(func(enabled: bool): show_details = enabled; refresh())
	body.add_child(details)
	for batch: Dictionary in view.shop.batches:
		if int(batch.remaining) > 0:
			var copy: Dictionary = content_settings.copy
			var source: String = str(content_settings.source_labels.get(batch.source,copy.source_unknown))
			var quality: String = str(view.catalog.get("quality_levels",{}).get(batch.get("quality_id",""),{}).get("label",copy.quality_unknown))
			text(String(copy.batch_quality).format({"item":view.catalog.items.get(batch.item_id,{}).get("name",copy.item_unknown),"remaining":batch.remaining,"source":source,"quality":quality}),int(content_settings.layout.note_font))
	text("完整账簿", 20)
	for entry: Dictionary in GameState.ledger_view().slice(-40):
		var labels := {"divination":"问卜报酬","product":"商品交易","gift":"额外赠礼","procurement":"采购原料","material_sale":"出售原料","gather":"外出采集","research":"研究配方","craft":"制作商品","demand":"记下需求","use":"使用商品","review":"复盘","experience":"接待经验"}
		var record: Dictionary = entry.get("payment",entry.get("result",{}))
		var item_id: String = str(record.get("item_id",""))
		var item_name: String = ItemArt.name_for(visuals,item_id,view.catalog.items)
		var amount: String = " · %d 金币" % int(record.amount) if record.get("kind") == "coins" else (" · " + item_name if not item_name.is_empty() else "")
		var ledger_text: String = "%s%s" % [labels.get(entry.category,"经营记录"),amount]
		if show_details:
			ledger_text += " · "+ContentUI.format_time(int(entry.get("at",0)))
		if visuals.get("items",{}).has(item_id):
			_item_row(item_id,ledger_text)
		else:
			text(ledger_text,16)
	_use_history(view)

func _workshop(view: Dictionary) -> void:
	var copy: Dictionary = content_settings.copy
	text(copy.workshop_intro,int(content_settings.layout.body_font))
	var craft_config := preload("res://scripts/shop/craft_config.gd").load_config(view.catalog)
	if not craft_config.is_empty():
		var experiment := UI.button(craft_config.ui.copy.experiment,func(): host.open_craft())
		experiment.name = "CraftExperiment"
		experiment.disabled = not GameState.active_visit().is_empty()
		body.add_child(experiment)
	for id: String in view.catalog.recipes:
		var base: Dictionary = view.catalog.recipes[id]
		var state: Dictionary = view.get("recipe_states",{}).get(id,{})
		var row := _item_row(base.output,base.name)
		row.name = "RecipeActions_"+id
		if state.get("known",false):
			var selector := CardChoice.new()
			selector.name = "RecipeVariant_"+id
			selector.set_meta("recipe_id",id)
			selector.custom_minimum_size.x = float(content_settings.layout.picker_width)
			selector.fit_to_longest_item = false
			selector.add_item(copy.base_variant)
			selector.set_item_metadata(0,"")
			for variant_id: String in state.get("variant_ids",[]):
				selector.add_item(view.catalog.recipe_variants[variant_id].name)
				selector.set_item_metadata(selector.item_count-1,variant_id)
			var selected := 0
			for index: int in range(selector.item_count):
				if selector.get_item_metadata(index) == selected_variants.get(id,""): selected = index
			selector.select(selected)
			var selected_id: String = selector.get_item_metadata(selected)
			selector.item_selected.connect(func(index: int):
				selected_variants[id] = str(selector.get_item_metadata(index))
				refresh())
			row.add_child(selector)
			var recipe := ContentUI.selected_recipe(view.catalog,id,selected_id)
			var params := {"recipe_id":id}
			if not selected_id.is_empty(): params["variant_id"] = selected_id
			var craft: Button
			if view.catalog.get("debug_one_click",false):
				craft = _content_action(String(copy.craft).format({"minutes":recipe.minutes,"energy":recipe.energy}),"craft_item",params,_can_craft(view,recipe))
			else:
				craft = UI.button(String(copy.craft).format({"minutes":recipe.minutes,"energy":recipe.energy}),func(): host.open_craft(selected_id if not selected_id.is_empty() else id),"primary")
				craft.disabled = not _can_craft(view,recipe)
				craft.set_meta("action_kind","craft_open")
				craft.set_meta("action_params",params.duplicate(true))
			craft.name = "CraftRecipe_"+id
			row.add_child(craft)
			_row_text(row,copy.known,int(content_settings.layout.note_font))
			_recipe_information(view,recipe,row)
		else:
			_row_text(row,copy.inspiration_pending if state.get("inspired",false) else copy.no_inspiration,int(content_settings.layout.body_font))
			_recipe_information(view,base,row)
			var tags: Array = base.get("need_tags",[]).duplicate()
			var needs: Array = tags.map(func(tag: String) -> String: return str(view.catalog.need_tags[tag]))
			var record: String = String(copy.demand_text).format({"item":view.catalog.items[base.output].name,"needs":"、".join(needs)})
			var can_record: bool = not GameState.active_visit().is_empty() and int(view.items.get(base.output,0)) <= 0
			var demand := _content_action(copy.register_demand,"register_demand",{"recipe_id":id,"need_tags":tags,"text":record},can_record)
			demand.name = "RegisterDemand_"+id
			row.add_child(demand)
			var research := _content_action(String(copy.research).format({"coins":base.coins,"minutes":base.research_minutes,"energy":base.research_energy}),"research_recipe",{"recipe_id":id},state.get("researchable",false))
			research.name = "ResearchRecipe_"+id
			row.add_child(research)
	text(copy.demand_heading,int(content_settings.layout.heading_font))
	text(copy.demand_authorship,int(content_settings.layout.note_font))
	for demand: Dictionary in view.shop.demands.values():
		var kind: String = str(demand.get("source",{}).get("kind","shop_record"))
		var label: String = copy.demand_advice if kind == "advice_need" else (copy.demand_statement if kind == "npc_statement" else copy.demand_shop)
		text(label+" · "+str(demand.get("text","")),int(content_settings.layout.body_font))

func _market(view: Dictionary) -> void:
	var learning: Dictionary = GameState.learning_view()
	if not learning.is_empty():
		body.add_child(UI.paper_heading(learning.copy.book))
		for course: Dictionary in learning.rows:
			var book_row := HBoxContainer.new()
			body.add_child(book_row)
			var book_title := UI.label(course.title,int(learning.config.layout.font))
			book_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			book_row.add_child(book_title)
			var book_button := UI.button(String(learning.copy.buy_book_short).format({"coins":course.book_price}),func(): await host.run_learning_action("purchase_method_book",{"method_id":course.method_id}))
			book_button.name = "MarketBook_"+str(course.method_id)
			book_button.disabled = course.book_registered or course.mastered
			book_row.add_child(book_button)
		body.add_child(UI.button(learning.copy.title,func(): host.open_learning()))
		body.add_child(UI.Materials.make_divider())
	var player: Dictionary = GameState.player_snapshot().get("player", {})
	text("当前金币 %d · 采购消耗 10 分钟与 2 精力；出售消耗 5 分钟。" % int(player.get("coins", 0)))
	var tabs := HBoxContainer.new()
	body.add_child(tabs)
	tabs.add_child(UI.button("买入原料", func():
		market_mode = "buy"
		refresh()))
	tabs.add_child(UI.button("卖出原料", func():
		market_mode = "sell"
		refresh()))
	var quantity_row := HBoxContainer.new()
	body.add_child(quantity_row)
	var quantity_label := UI.label(content_settings.copy.quantity,int(content_settings.layout.body_font))
	quantity_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	quantity_row.add_child(quantity_label)
	market_action_buttons.clear()
	var quantity := SpinBox.new()
	quantity.name = "MarketQuantity"
	quantity.custom_minimum_size.x = float(content_settings.layout.quantity_width)
	quantity.add_theme_font_size_override("font_size",int(content_settings.layout.body_font))
	quantity.min_value = int(content_settings.layout.quantity_min)
	quantity.max_value = int(content_settings.layout.quantity_max)
	quantity.step = int(content_settings.layout.quantity_step)
	quantity.value = market_quantity
	quantity.value_changed.connect(func(value: float):
		market_quantity = int(value)
		_update_market_action_buttons())
	quantity_row.add_child(quantity)
	text("买入：原料会进入储物柜。卖出：仅出售现有库存，不会出售成品。", 15)
	for id: String in view.catalog.items:
		var item: Dictionary = view.catalog.items[id]
		if item.kind != "material":
			continue
		var stock := int(view.items.get(id, 0))
		var unit_price := int(item.buy if market_mode == "buy" else item.sell)
		var row := _item_row(id, "%s · %d 金币/份 · 库存 %d" % [item.name, unit_price, stock])
		var primary: String = str(item.get("primary_source","purchase"))
		_row_text(row,String(content_settings.copy.source_format).format({"source":content_settings.source_labels.get(primary,content_settings.copy.source_unknown)}),int(content_settings.layout.note_font))
		if market_mode == "buy":
			if not item.get("purchase_allowed",true):
				continue
			var buy_label := "购买一份" if market_quantity == 1 else "购买 ×%d" % market_quantity
			var buy_button := _content_action(buy_label,"procure_item",{"item_id":id,"quantity":market_quantity})
			buy_button.name = "BuyMaterial_"+id
			buy_button.set_meta("item_id", id)
			buy_button.set_meta("trade_kind", "buy")
			if int(view.shop.reputation) < int(item.get("requires_reputation", 0)):
				buy_button.disabled = true
				buy_button.tooltip_text = "需要口碑 %d" % int(item.requires_reputation)
			market_action_buttons.append(buy_button)
			row.add_child(buy_button)
		else:
			var sell_button := _content_action("出售 ×%d" % market_quantity,"sell_material",{"item_id":id,"quantity":market_quantity},stock >= market_quantity)
			sell_button.name = "SellMaterial_"+id
			sell_button.set_meta("item_id", id)
			sell_button.set_meta("trade_kind", "sell")
			sell_button.disabled = stock < market_quantity
			market_action_buttons.append(sell_button)
			row.add_child(sell_button)
		if item.has("requires_reputation"):
			text("%s · 解锁口碑 %d" % [item.name, int(item.requires_reputation)], 14)
	if market_mode == "buy":
		for visit: Dictionary in GameState.player_snapshot().get("visits", []):
			if visit.phase == "ended" and visit.visit_id not in view.shop.gift_visits:
				var guest: Dictionary = GameState.divination_view(visit.visit_id).get("guest", {})
				button("收下" + str(guest.get("name","客人")) + "留下的原料", func(): await act("receive_material_gift", {"visit_id":visit.visit_id}))


func _update_market_action_buttons() -> void:
	var stock_view: Dictionary = GameState.shop_view().get("items", {})
	for trade_button: Button in market_action_buttons:
		var item_id := str(trade_button.get_meta("item_id", ""))
		var kind := str(trade_button.get_meta("trade_kind", "buy"))
		if kind == "buy":
			trade_button.text = "购买一份" if market_quantity == 1 else "购买 ×%d" % market_quantity
		else:
			trade_button.text = "出售 ×%d" % market_quantity
			trade_button.disabled = int(stock_view.get(item_id, 0)) < market_quantity
		trade_button.set_meta("action_params",{"item_id":item_id,"quantity":market_quantity})

func _gathering(view: Dictionary) -> void:
	text("选择一个采集点。不同地点的材料、耗时和每日次数独立计算。")
	var copy: Dictionary = content_settings.copy
	var site_ids: Array = view.catalog.gather_sites.keys()
	site_ids.sort()
	for id: String in site_ids:
		var site: Dictionary = view.catalog.gather_sites[id]
		var state: Dictionary = view.get("gather_states",{}).get(id,{})
		var drops: PackedStringArray = []
		for item_id: String in site.drops:
			drops.append("%s ×%d" % [view.catalog.items[item_id].name, int(site.drops[item_id])])
		var panel := UI.panel("plain")
		body.add_child(panel)
		var column := VBoxContainer.new()
		panel.add_child(column)
		column.add_child(UI.label(site.name,int(content_settings.layout.heading_font),UI.GOLD))
		column.add_child(UI.label(String(copy.gather_drops).format({"materials":"、".join(drops)}),int(content_settings.layout.note_font)))
		var weather: String = str(content_settings.weather_labels.get(state.get("weather_id",""),copy.weather_unknown))
		column.add_child(UI.label(String(copy.weather).format({"weather":weather}) if state.get("weather_known",false) else copy.weather_unknown,int(content_settings.layout.body_font)))
		column.add_child(UI.label(String(copy.gather_remaining).format({"remaining":state.get("remaining",0)}),int(content_settings.layout.note_font)))
		column.add_child(UI.label(String(copy.gather_window).format({"start":ContentUI.format_time(int(site.opening)),"end":ContentUI.format_time(int(site.closing)),"minutes":site.minutes,"energy":site.energy}),int(content_settings.layout.note_font),UI.MUTED))
		column.add_child(UI.label(copy.gather_open if state.get("open",false) else (copy.gather_weather_blocked if not state.get("weather_allowed",true) else copy.gather_closed),int(content_settings.layout.note_font)))
		var gather := _content_action(String(copy.gather_action).format({"site":site.name}),"gather_material",{"site_id":id},state.get("open",false))
		gather.name = "GatherSite_"+id
		column.add_child(gather)

func _item_texture(id: String, small: bool = true) -> Texture2D:
	return ItemArt.texture_for(visuals,id,small)

func _item_row(id: String, label: String) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(group)
	var information := HBoxContainer.new()
	group.add_child(information)
	var item: Dictionary = GameState.shop_view().get("catalog",{}).get("items",{}).get(id,{})
	var icon := ItemArt.icon_control(visuals,id,item.get("purposes",[]))
	information.add_child(icon)
	var line := UI.label(label,20)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	information.add_child(line)
	var actions := VBoxContainer.new()
	actions.name = "ItemActions"
	actions.add_theme_constant_override("separation",int(content_settings.get("layout",{}).get("action_gap",12)))
	actions.child_entered_tree.connect(func(child: Node):
		if child is Button:
			child.clip_text = false
			child.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING)
	group.add_child(actions)
	return actions

func _inventory_item_actions(view: Dictionary, id: String) -> void:
	if int(view.items.get(id,0)) <= 0:
		return
	var item: Dictionary = view.catalog.items.get(id,{})
	var item_name := ItemArt.name_for(visuals,id,view.catalog.items)
	var row := _item_row(id,"%s × %d" % [item_name,int(view.items.get(id,0))])
	if item.get("kind") == "material":
		row.add_child(UI.button("出售一份",func(): await act("sell_material",{"item_id":id})))
	elif item.get("kind") == "product":
		var sell := _content_action("出售给当前来客","sell_product",{"item_id":id},not GameState.active_visit().is_empty())
		row.add_child(sell)
		var actions: Array = _use_actions(view,id).filter(func(action: Dictionary) -> bool: return action.target != "sale")
		_add_use_actions(row,actions,id)
		if actions.is_empty():
			var kinds: Array = [item.get("effect",{}).get("kind","")]
			for effect: Dictionary in item.get("additional_effects",[]): kinds.append(effect.kind)
			var note: String = content_settings.copy.use_sale_required if "event" in kinds or "relationship" in kinds else (content_settings.copy.use_waiting_required if "patience" in kinds else content_settings.copy.use_visit_required)
			text(note,int(content_settings.layout.note_font))

func _row_text(row: BoxContainer, value: String, font_size: int) -> void:
	var label := UI.label(value,font_size)
	row.get_parent().add_child(label)
	row.get_parent().move_child(label,row.get_index())

func _recipe_information(view: Dictionary, recipe: Dictionary, row: BoxContainer) -> void:
	for line: String in ContentUI.recipe_materials(recipe,view,content_settings):
		_row_text(row,line,int(content_settings.layout.note_font))
	var quality: String = str(view.catalog.get("quality_levels",{}).get(recipe.get("quality","standard"),{}).get("label",content_settings.copy.quality_unknown))
	_row_text(row,String(content_settings.copy.quality).format({"quality":quality}),int(content_settings.layout.note_font))

func _can_craft(view: Dictionary, recipe: Dictionary) -> bool:
	var snapshot: Dictionary = GameState.player_snapshot()
	if not GameState.active_visit().is_empty() or int(snapshot.get("player",{}).get("energy",0)) < int(recipe.get("energy",0)):
		return false
	var closing: int = int(view.catalog.get("rules",{}).get("closing_minute",0))
	if int(snapshot.get("clock_minutes",0))%1440+int(recipe.get("minutes",0)) > closing:
		return false
	return recipe.get("ingredients",{}).keys().all(func(id: String) -> bool: return int(view.items.get(id,0)) >= int(recipe.ingredients[id]))

func _content_action(label: String, kind: String, params: Dictionary, enabled: bool = true) -> Button:
	var control := Button.new()
	control.text = label
	control.clip_text = false
	control.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	control.custom_minimum_size = Vector2(content_settings.layout.action_width,content_settings.layout.action_height)
	control.add_theme_font_size_override("font_size",int(content_settings.layout.body_font))
	control.focus_mode = Control.FOCUS_ALL
	control.disabled = not enabled
	control.set_meta("action_kind",kind)
	control.set_meta("action_params",params.duplicate(true))
	control.pressed.connect(func(): await act(kind,control.get_meta("action_params",{})))
	control.pressed.connect(func():
		if is_inside_tree():
			var audio := get_tree().root.find_child("ShopAudio",true,false)
			if audio != null: audio.play_ui("click"))
	return control

func _use_actions(view: Dictionary, item_id: String) -> Array:
	var active: Dictionary = GameState.active_visit()
	var visit := {} if active.is_empty() else {"visit_id":active.visit_id,"npc_id":active.npc_id}
	return ContentUI.use_actions(item_id,view.catalog.items.get(item_id,{}),view,GameState.people_view(),visit,content_settings)

func _add_use_actions(parent: BoxContainer, actions: Array, item_id: String) -> void:
	if actions.is_empty():
		return
	var waiting: Array = actions.filter(func(row: Dictionary) -> bool: return row.target == "waiting")
	if not waiting.is_empty():
		var target := CardChoice.new()
		target.name = "ProductUseTarget_"+item_id
		target.fit_to_longest_item = false
		target.custom_minimum_size.x = float(content_settings.layout.picker_width)
		for action: Dictionary in waiting:
			target.add_item(action.label)
			target.set_item_metadata(target.item_count-1,action.params.duplicate(true))
		var use := _content_action(waiting[0].label,"use_product",waiting[0].params)
		use.name = "UseWaitingProduct_"+item_id
		target.item_selected.connect(func(index: int):
			use.text = target.get_item_text(index)
			use.set_meta("action_params",target.get_item_metadata(index).duplicate(true)))
		parent.add_child(target)
		parent.add_child(use)
	for action: Dictionary in actions:
		if action.target == "waiting": continue
		var use := _content_action(action.label,"use_product",action.params)
		use.name = "UseProduct_"+item_id+"_"+str(action.target)
		parent.add_child(use)

func _use_history(view: Dictionary) -> void:
	if view.shop.get("uses",[]).is_empty(): return
	text(content_settings.copy.use_heading,int(content_settings.layout.heading_font))
	for use: Dictionary in view.shop.uses.slice(-int(content_settings.layout.history_rows)):
		var item_name: String = str(view.catalog.items.get(use.get("item_id",""),{}).get("name",content_settings.copy.item_unknown))
		var clock: String = ContentUI.format_time(int(use.get("at",0)))
		text(String(content_settings.copy.use_title).format({"item":item_name,"hour":clock.get_slice(":",0),"minute":clock.get_slice(":",1)}),int(content_settings.layout.body_font))
		var report := {}
		if not str(use.get("visit_id","")).is_empty():
			report = GameState.divination_view(use.visit_id).get("event",{}).get("report",{})
		for component: Dictionary in use.get("component_results",[]):
			var actual := {}
			if component.get("feedback_refs",[]).any(func(ref: Dictionary) -> bool: return ref.get("kind") == "npc_feedback" and ref.get("source_id") == report.get("feedback_id")):
				for ref: Dictionary in report.get("item_component_refs",[]):
					if ref.get("item_use_id") == use.item_use_id and ref.get("component_id") == component.component_id: actual = ref
			text(str(content_settings.effect_labels.get(component.get("kind",""),content_settings.copy.result_other))+" · "+ContentUI.component_text(component,content_settings,actual),int(content_settings.layout.note_font))
			for reference: Dictionary in component.get("feedback_refs",[]):
				text(str(view.catalog.get("feedback_copy",{}).get(reference.get("kind",""),content_settings.copy.result_other)),int(content_settings.layout.note_font))
		var source_button := UI.button(content_settings.copy.use_details,func():
			expanded_uses[use.item_use_id] = not expanded_uses.get(use.item_use_id,false)
			refresh())
		source_button.name = "UseResultSource_"+str(use.get("item_use_id",""))
		source_button.set_meta("item_use_id",use.get("item_use_id",""))
		source_button.set_meta("source_batches",use.get("source_batches",[]).duplicate(true))
		body.add_child(source_button)
		if expanded_uses.get(use.get("item_use_id",""),false):
			text(String(content_settings.copy.use_batches).format({"count":use.get("source_batches",[]).size()}),int(content_settings.layout.note_font))
			for source: Dictionary in use.get("source_batches",[]):
				var batch := {}
				for existing: Dictionary in view.shop.get("batches",[]):
					if existing.get("batch_id") == source.get("batch_id"): batch = existing
				var source_label: String = str(content_settings.source_labels.get(batch.get("source",""),content_settings.copy.source_unknown))
				var quality_label: String = str(view.catalog.get("quality_levels",{}).get(source.get("quality_id",batch.get("quality_id","")),{}).get("label",content_settings.copy.quality_unknown))
				text(String(content_settings.copy.use_batch).format({"quantity":source.get("quantity",0),"source":source_label,"quality":quality_label}),int(content_settings.layout.note_font))
			if not str(use.get("visit_id","")).is_empty():
				var record := UI.button(content_settings.copy.feedback_open,func():
					if host.has_method("show_history"): host.show_history())
				record.set_meta("visit_id",use.visit_id)
				record.disabled = not host.has_method("show_history")
				body.add_child(record)

func _build_inventory_shelves(view: Dictionary) -> void:
	if not is_instance_valid(shelf_view):
		shelf_view = ShelfView.new()
		shelf_view.name = "InventoryShelves"
		scene_visual.add_child(shelf_view)
		shelf_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shelf_view.z_index = scene_visual.interaction_z_index()
		shelf_view.item_selected.connect(_on_shelf_item_selected)
		shelf_view.setup(scene_visual,visuals)
	elif shelf_view.visuals != visuals:
		shelf_view.setup(scene_visual,visuals)
	if is_instance_valid(scene_visual.motion_controller):
		scene_visual.motion_controller.bind_shelf(shelf_view)
	shelf_view.update_inventory(view,GameState.player_snapshot(),cabinet_open)

func _on_shelf_item_selected(item_id: String) -> void:
	selected_inventory_item = item_id
	drawer.set_expanded(true)
	refresh()

func text(value: String, size: int = 18) -> void:
	body.add_child(UI.label(value,size))

func button(value: String, callback: Callable) -> void:
	body.add_child(UI.button(value,callback))

func act(kind: String, extra: Dictionary = {}) -> void:
	if content_action_pending: return
	content_action_pending = true
	var result: Dictionary = await ArrivalUI.run_action(host,self,kind,extra)
	content_action_pending = false
	if result.get("success",false) and is_inside_tree():
		refresh()

